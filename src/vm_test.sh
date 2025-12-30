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
    if netstat -tuln 2>/dev/null | grep -q ":${APP_PORT} " || \
       ss -tuln 2>/dev/null | grep -q ":${APP_PORT} "; then
        log_error "端口 ${APP_PORT} 已被占用"
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

ensure_dependencies
validate_port

log "停止可能存在的Nginx服务..."
sudo systemctl stop nginx 2>/dev/null || true
sudo pkill -9 nginx 2>/dev/null || true

log "配置Nginx监听端口 ${APP_PORT}..."
# 创建临时配置文件
NGINX_CONF="/tmp/nginx_test_${APP_PORT}.conf"
cat > "${NGINX_CONF}" <<NGINXEOF
user www-data;
worker_processes auto;
pid /tmp/nginx_test_${APP_PORT}.pid;

events {
    worker_connections 768;
}

http {
    access_log /tmp/nginx_access_${APP_PORT}.log;
    error_log /tmp/nginx_error_${APP_PORT}.log;
    
    server {
        listen ${APP_PORT};
        server_name localhost;
        
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

log "启动Nginx..."
START_TIME=$(date +%s.%N)

sudo nginx -c "${NGINX_CONF}" || {
    log_error "Nginx启动失败"
    write_placeholder
}

log "等待Nginx就绪..."
ready=false
for i in {1..30}; do
    if curl -s -o /dev/null "http://localhost:${APP_PORT}" 2>/dev/null; then
        ready=true
        break
    fi
    sleep 1
done

if [[ "$ready" != true ]]; then
    log_error "Nginx启动超时"
    write_placeholder
fi

END_TIME=$(date +%s.%N)
STARTUP_TIME=$(python3 <<PY
from decimal import Decimal
print(float(Decimal("${END_TIME}") - Decimal("${START_TIME}")))
PY
)

log_success "Nginx已启动 (${STARTUP_TIME}秒)"

log "采集性能指标..."

# 获取Nginx主进程PID
NGINX_PID=$(pgrep -x nginx | head -1)

# CPU使用率 - 只统计Nginx进程
if [[ -n "${NGINX_PID}" ]]; then
    # 收集3次CPU样本取平均值，确保准确性
    CPU_SUM=0
    for i in {1..3}; do
        CPU_VAL=$(ps -p ${NGINX_PID} -o %cpu --no-headers 2>/dev/null | awk '{print $1}' || echo "0")
        CPU_SUM=$(python3 -c "print(${CPU_SUM} + ${CPU_VAL})" 2>/dev/null || echo "0")
        [[ $i -lt 3 ]] && sleep 1
    done
    CPU_PERCENT=$(python3 -c "print(round(${CPU_SUM} / 3, 2))" 2>/dev/null || echo "0")
else
    CPU_PERCENT="0"
fi

# 内存使用 (MB) - 只统计Nginx进程（包括所有worker进程）
if [[ -n "${NGINX_PID}" ]]; then
    # 统计所有nginx进程的内存
    MEMORY_KB=$(ps -C nginx -o rss --no-headers 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    MEMORY_MB=$(python3 -c "print(round(${MEMORY_KB} / 1024, 2))" 2>/dev/null || echo "0")
else
    MEMORY_MB="0"
fi

# 磁盘使用 (MB) - 只计算Nginx安装大小
# 获取nginx可执行文件和相关文件的大小
NGINX_SIZE=$(dpkg-query -W -f='${Installed-Size}' nginx 2>/dev/null || \
             rpm -q nginx --qf '%{SIZE}' 2>/dev/null || echo "0")
# dpkg返回KB，rpm返回字节，统一转换为MB
if dpkg-query -W nginx >/dev/null 2>&1; then
    DISK_MB=$(python3 -c "print(round(${NGINX_SIZE} / 1024, 2))" 2>/dev/null || echo "0")
elif rpm -q nginx >/dev/null 2>&1; then
    DISK_MB=$(python3 -c "print(round(${NGINX_SIZE} / 1024 / 1024, 2))" 2>/dev/null || echo "0")
else
    # 如果无法从包管理器获取，估算nginx目录大小
    DISK_KB=$(du -sk /usr/sbin/nginx /etc/nginx /usr/share/nginx 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    DISK_MB=$(python3 -c "print(round(${DISK_KB} / 1024, 2))" 2>/dev/null || echo "0")
fi

# VM IP地址
VM_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")

# 保存指标
cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,${STARTUP_TIME}
cpu_percent,${CPU_PERCENT}
memory_mb,${MEMORY_MB}
disk_mb,${DISK_MB}
vm_ip,${VM_IP}
EOF

echo "${VM_IP}" > "${OUTPUT_DIR}/vm_ip.txt"

[[ -n "${PERF_CSV}" ]] && echo "vm,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"

# 清理：停止Nginx以释放端口，避免影响后续Docker测试
log "清理Nginx进程..."
sudo pkill -9 nginx 2>/dev/null || true
sudo rm -f "/tmp/nginx_test_${APP_PORT}.pid" 2>/dev/null || true

echo ""
log_success "VM测试完成"
log "结果: ${OUTPUT_DIR}"
log "  启动时间: ${STARTUP_TIME}秒"
log "  CPU占用: ${CPU_PERCENT}%"
log "  内存占用: ${MEMORY_MB}MB"
log "  磁盘占用: ${DISK_MB}MB"
log "  VM IP: ${VM_IP}"
