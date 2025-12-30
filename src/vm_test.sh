#!/bin/bash
# =============================================================================
# VMWare Linux 虚拟机上的 Nginx 部署与性能采集脚本
# 关注：启动时间、CPU占用、内存占用、磁盘占用，输出CSV
# =============================================================================
# 说明：
#   此脚本在 VMWare 虚拟机内直接运行，测试虚拟机环境的性能
#
# 使用方法：
#   在 VMWare Linux 虚拟机中运行：
#   bash vm_test.sh
#   或指定端口：
#   bash vm_test.sh --app-port 9090
#
# 要求：
#   - Ubuntu/Debian/CentOS 等主流 Linux 发行版
#   - 需要 sudo 权限（用于安装软件和启动 Nginx）
#   - 需要互联网连接（首次运行时安装依赖）
# =============================================================================

set -euo pipefail

VM_NAME="vmware-nginx"
APP_PORT=8080
OUTPUT_DIR="./results/vm"
PERF_CSV=""
IMAGE="nginx:latest"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[VM]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }

write_placeholder() {
    log_warning "测试失败，生成占位数据"
    mkdir -p "${OUTPUT_DIR}"
    cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,0
cpu_percent,0
memory_mb,0
disk_mb,0
vm_ip,unavailable
EOF
    [[ -n "${PERF_CSV}" ]] && echo "vm,0,0,0,0" >> "${PERF_CSV}"
    exit 0
}

ensure_dependencies() {
    local missing=()
    
    command -v nginx >/dev/null 2>&1 || missing+=("nginx")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warning "缺少依赖: ${missing[*]}"
        log "尝试自动安装..."
        
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y "${missing[@]}" || {
                log_error "安装失败，请手动安装: ${missing[*]}"
                write_placeholder
            }
        else
            log_error "请手动安装: ${missing[*]}"
            write_placeholder
        fi
    fi
}

validate_port() {
    # 仅检查 VM_IP:APP_PORT 是否被占用（允许 127.0.0.1:APP_PORT 由 Docker 使用）
    if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -q "^${VM_IP}:${APP_PORT}$"; then
        log_error "端口 ${VM_IP}:${APP_PORT} 已被占用"
        log "请使用 --app-port 指定其他端口"
        exit 1
    fi
    if netstat -tuln 2>/dev/null | awk '{print $4}' | grep -q "^${VM_IP}:${APP_PORT}$"; then
        log_error "端口 ${VM_IP}:${APP_PORT} 已被占用"
        log "请使用 --app-port 指定其他端口"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm-name) VM_NAME="$2"; shift 2;;
            --app-port) APP_PORT="$2"; shift 2;;
            --output-dir) OUTPUT_DIR="$2"; shift 2;;
            --perf-csv) PERF_CSV="$2"; shift 2;;
            *) log_error "未知参数: $1"; exit 1;;
        esac
    done
}

parse_args "$@"
mkdir -p "${OUTPUT_DIR}"

# VM IP地址（用于绑定监听地址，避免占用 127.0.0.1 与 Docker 冲突）
VM_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")

ensure_dependencies
validate_port

log "停止可能存在的Nginx服务..."
sudo systemctl stop nginx 2>/dev/null || true
sudo pkill -9 nginx 2>/dev/null || true

# 确保nginx完全停止，清理所有残留进程和文件
sleep 1
sudo rm -f /tmp/nginx_test_*.pid 2>/dev/null || true
sudo rm -f /tmp/nginx_*.log 2>/dev/null || true
sudo rm -f /var/run/nginx.pid 2>/dev/null || true

# 清理系统缓存，确保冷启动测试（与Docker公平对比）
sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true

log "配置Nginx监听端口 ${APP_PORT}..."
# 创建临时配置文件
NGINX_CONF="/tmp/nginx_test_${APP_PORT}.conf"

# 获取CPU核心数（用于worker_processes配置）
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)

cat > "${NGINX_CONF}" <<NGINXEOF
user www-data;
worker_processes ${CPU_CORES};
worker_cpu_affinity auto;
worker_rlimit_nofile 65535;
pid /tmp/nginx_test_${APP_PORT}.pid;

events {
    use epoll;
    worker_connections 20480;
    multi_accept on;
}

http {
    access_log off;
    error_log off;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 10000;
    
    server {
        # 只监听 VM 的内网 IP，避免与 Docker 在同一端口冲突
        listen ${VM_IP}:${APP_PORT} reuseport;
        server_name ${VM_IP};
        
        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }
    }
}
NGINXEOF

# 如果nginx html目录不存在，使用默认HTML
if [[ ! -d "/usr/share/nginx/html" ]]; then
    sudo mkdir -p /usr/share/nginx/html
    echo "<html><body><h1>Welcome to nginx!</h1></body></html>" | sudo tee /usr/share/nginx/html/index.html >/dev/null
fi

# ============================================================================
# 【启动时间测量】
# 测量包含：1. 虚拟机系统引导时间 (Boot Time) + 2. Nginx 服务就绪时间
# 与 Docker 对比时，VM 的总启动时间应包含 OS 引导开销
# ============================================================================
log "获取虚拟机系统引导时间..."
BOOT_TIME=0
if command -v systemd-analyze >/dev/null 2>&1; then
    # 提取总启动时间（例如：Startup finished in 2.123s (kernel) + 15.432s (userspace) = 17.555s）
    BOOT_TIME=$(systemd-analyze | grep -oP "finished in .* = \K[0-9.]+(?=s)" || echo 0)
    if [[ "${BOOT_TIME}" == "0" ]]; then
        # 兼容不同版本的 systemd-analyze 输出格式
        BOOT_TIME=$(systemd-analyze | awk -F'=' '/Startup finished/ {print $2}' | awk '{print $1}' | sed 's/s//' || echo 0)
    fi
    log "系统引导时间: ${BOOT_TIME}秒"
else
    log_warning "未找到 systemd-analyze，无法获取准确的系统引导时间"
fi

log "启动Nginx服务并测量就绪时间..."
START_TIME=$(date +%s.%N)

# 启动nginx
sudo nginx -c "${NGINX_CONF}" || {
    log_error "Nginx启动失败"
    write_placeholder
}

log "等待Nginx完全就绪..."
ready=false
success_count=0

# 等待nginx就绪并进行健康检查（连续3次HTTP 200）
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://${VM_IP}:${APP_PORT}" 2>/dev/null | grep -q "200"; then
        success_count=$((success_count + 1))
        if [[ $success_count -ge 3 ]]; then
            ready=true
            break
        fi
        sleep 0.1
    else
        success_count=0
        sleep 0.3
    fi
done

if [[ "$ready" != true ]]; then
    log_error "Nginx启动超时"
    write_placeholder
fi

END_TIME=$(date +%s.%N)
STARTUP_TIME=$(python3 <<PY
from decimal import Decimal
nginx_ready_time = Decimal("${END_TIME}") - Decimal("${START_TIME}")
boot_time = Decimal("${BOOT_TIME}")
# 总启动时间 = 系统引导时间 + 应用就绪时间
total_time = boot_time + nginx_ready_time
print(float(total_time.quantize(Decimal("0.001"))))
PY
)

log_success "Nginx服务已就绪 (应用启动: $(python3 -c "print(round(${END_TIME}-${START_TIME}, 3))")秒, 总计: ${STARTUP_TIME}秒)"

# ============================================================================
# 【性能指标采集】
# 在有负载情况下采集，确保CPU有真实消耗
# ============================================================================
log "采集性能指标..."

# 【关键修复】先产生负载，再采集CPU
log "产生负载以获取真实CPU数据..."
for i in {1..50}; do
    curl -s -o /dev/null "http://${VM_IP}:${APP_PORT}" &
done
wait
sleep 0.5

# ============================================================================
# 【CPU测量】固定负载窗口 + 进程 CPU 时间差（必然非0，更稳定）
# 口径：nginx 全进程 utime+stime 的增量 / 窗口时长
# ============================================================================
get_nginx_cpu_ticks() {
    python3 - <<'PY'
import glob
total = 0
for p in glob.glob("/proc/[0-9]*/comm"):
    try:
        with open(p, "r", encoding="utf-8") as f:
            if f.read().strip() != "nginx":
                continue
        stat_path = p.replace("/comm", "/stat")
        with open(stat_path, "r", encoding="utf-8") as f:
            parts = f.read().split()
        # utime=14, stime=15 (1-based), split()后索引13/14
        total += int(parts[13]) + int(parts[14])
    except Exception:
        pass
print(total)
PY
}

HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
CPU_T0=$(get_nginx_cpu_ticks)
T0=$(date +%s.%N)

# 固定负载窗口：持续 2 秒打请求（比“采样瞬时%cpu”更可靠）
LOAD_END=$((SECONDS + 2))
while [[ ${SECONDS} -lt ${LOAD_END} ]]; do
    for j in {1..25}; do
        curl -s -o /dev/null "http://${VM_IP}:${APP_PORT}/" &
    done
    wait
done

CPU_T1=$(get_nginx_cpu_ticks)
T1=$(date +%s.%N)

CPU_PERCENT=$(python3 - <<PY
from decimal import Decimal
dt = float(Decimal("${T1}") - Decimal("${T0}"))
dcpu = (${CPU_T1} - ${CPU_T0}) / float(${HZ})
val = 0.0 if dt <= 0 else (dcpu / dt) * 100.0
print(round(val, 2))
PY
)

# ============================================================================
# 【内存测量】统计所有nginx进程的RSS内存
# 方法：ps -C nginx -o rss，与Docker的进程级统计对等
# ============================================================================
MEMORY_KB=$(ps -C nginx -o rss --no-headers 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
MEMORY_MB=$(python3 -c "print(round(${MEMORY_KB} / 1024, 2))" 2>/dev/null || echo "0")

# ============================================================================
# 【磁盘测量】统计nginx相关的所有文件
# 包括：可执行文件、配置文件、模块、日志目录、html目录、依赖库
# 与Docker镜像包含的内容对等
# ============================================================================
DISK_KB=0

# nginx可执行文件和核心模块
if [[ -f /usr/sbin/nginx ]]; then
    NGINX_BIN_KB=$(du -sk /usr/sbin/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_BIN_KB))
fi

# nginx配置目录
if [[ -d /etc/nginx ]]; then
    NGINX_CONF_KB=$(du -sk /etc/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_CONF_KB))
fi

# nginx html目录
if [[ -d /usr/share/nginx ]]; then
    NGINX_HTML_KB=$(du -sk /usr/share/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_HTML_KB))
fi

# nginx模块目录
if [[ -d /usr/lib/nginx ]]; then
    NGINX_MOD_KB=$(du -sk /usr/lib/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_MOD_KB))
fi

# nginx日志目录
if [[ -d /var/log/nginx ]]; then
    NGINX_LOG_KB=$(du -sk /var/log/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_LOG_KB))
fi

# nginx运行时目录
if [[ -d /var/lib/nginx ]]; then
    NGINX_VAR_KB=$(du -sk /var/lib/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_VAR_KB))
fi

# nginx依赖的共享库（估算主要依赖）
# 修复：过滤掉 ldd 中不是绝对路径的条目（如 linux-vdso、地址等），避免算出来过小
NGINX_LIBS_KB=$(
    ldd /usr/sbin/nginx 2>/dev/null \
    | awk '{for (i=1;i<=NF;i++) if ($i ~ /^\//) print $i}' \
    | sort -u \
    | xargs -r -I{} du -sk {} 2>/dev/null \
    | awk '{sum+=$1} END {print sum+0}'
)
DISK_KB=$((DISK_KB + NGINX_LIBS_KB))

DISK_MB=$(python3 -c "print(round(${DISK_KB} / 1024, 2))" 2>/dev/null || echo "0")

# 保存指标
cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,${STARTUP_TIME}
cpu_percent,${CPU_PERCENT}
memory_mb,${MEMORY_MB}
disk_mb,${DISK_MB}
vm_ip,${VM_IP}
EOF

# 为 analyze_results.py 生成额外的结果文件，确保分析脚本能正确读取
echo "${STARTUP_TIME}" > "${OUTPUT_DIR}/startup_time.txt"
echo "${MEMORY_MB}" > "${OUTPUT_DIR}/used_memory_mb.txt"
echo "${DISK_KB}" | awk '{print $1 * 1024}' > "${OUTPUT_DIR}/disk_actual_bytes.txt"
nproc > "${OUTPUT_DIR}/configured_cpu.txt"
echo "${VM_IP}" > "${OUTPUT_DIR}/vm_ip.txt"

[[ -n "${PERF_CSV}" ]] && echo "vm,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"

# 注意：不清理Nginx，让压测脚本可以使用
# 清理工作由 cleanup.sh 或 run_experiment.sh 完成

echo ""
log_success "VM测试完成"
log "结果: ${OUTPUT_DIR}"
log "  启动时间: ${STARTUP_TIME}秒"
log "  CPU占用: ${CPU_PERCENT}%"
log "  内存占用: ${MEMORY_MB}MB"
log "  磁盘占用: ${DISK_MB}MB"
log "  VM IP: ${VM_IP}"
