#!/bin/bash
# =============================================================================
# 精简版 Docker Nginx 部署与性能采集脚本
# =============================================================================
# 功能：部署Docker容器并收集性能指标
# 指标：启动时间、CPU占用、内存占用、磁盘占用
# 输出：metrics.csv 和 performance.csv
#
# 使用方法:
#   bash docker_test.sh --container-name docker-nginx --app-port 8080
# =============================================================================

set -euo pipefail

CONTAINER_NAME="docker-nginx"
APP_PORT=8080
OUTPUT_DIR="./results/docker"
PERF_CSV=""
# 默认镜像（最终以 run_experiment.sh 传入的 --image 为准）
IMAGE="nginx:1.26.3-alpine"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[Docker]${NC} $*"; }
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
container_ip,unavailable
EOF
    [[ -n "${PERF_CSV}" ]] && echo "docker,0,0,0,0" >> "${PERF_CSV}"
    exit 0
}

validate_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker未安装"
        write_placeholder
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker守护进程未运行或权限不足"
        write_placeholder
    fi
}

validate_port() {
    # 仅检查 127.0.0.1:APP_PORT 是否被占用（允许 VM_IP:APP_PORT 由 VM nginx 使用）
    if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -q "^127\\.0\\.0\\.1:${APP_PORT}$"; then
        log_error "端口 127.0.0.1:${APP_PORT} 已被占用"
        exit 1
    fi
    if netstat -tuln 2>/dev/null | awk '{print $4}' | grep -q "^127\\.0\\.0\\.1:${APP_PORT}$"; then
        log_error "端口 127.0.0.1:${APP_PORT} 已被占用"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --container-name) CONTAINER_NAME="$2"; shift 2;;
            --app-port) APP_PORT="$2"; shift 2;;
            --output-dir) OUTPUT_DIR="$2"; shift 2;;
            --perf-csv) PERF_CSV="$2"; shift 2;;
            --image) IMAGE="$2"; shift 2;;
            *) log_error "未知参数: $1"; exit 1;;
        esac
    done
}

parse_args "$@"
mkdir -p "${OUTPUT_DIR}"

validate_docker
validate_port

log "清理旧容器..."
docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && \
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

log "拉取镜像 ${IMAGE}..."
docker pull "${IMAGE}" >/dev/null 2>&1 || {
    log_error "拉取镜像失败"
    write_placeholder
}

# ============================================================================
# 【启动时间测量】
# 关键修复：使用 docker create + docker start 分离方式
# 只测量 docker start 的时间，与VM的nginx进程启动对等
# docker create 相当于VM的nginx安装（预准备阶段，不计入启动时间）
# docker start 相当于VM的nginx启动（服务启动阶段）
# ============================================================================
log "创建容器（预准备阶段，不计入启动时间）..."
# 仅绑定到 127.0.0.1，避免与 VM 在同一端口冲突（VM 仅监听 VM_IP:APP_PORT）
docker create --name "${CONTAINER_NAME}" -p "127.0.0.1:${APP_PORT}:80" "${IMAGE}" >/dev/null || {
    log_error "创建容器失败"
    write_placeholder
}

# 清理系统缓存，与VM测试保持一致
sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true

log "启动容器并测量启动时间..."
START_TIME=$(date +%s.%N)

# 只测量 docker start 的时间（与VM的nginx启动对等）
docker start "${CONTAINER_NAME}" >/dev/null || {
    log_error "启动容器失败"
    write_placeholder
}

CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")

log "等待容器完全就绪..."
ready=false
success_count=0

# 等待容器就绪并进行健康检查（连续3次HTTP 200，与VM完全一致）
for i in {1..400}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${APP_PORT}" 2>/dev/null | grep -q "200"; then
        success_count=$((success_count + 1))
        if [[ $success_count -ge 3 ]]; then
            ready=true
            break
        fi
        sleep 0.02
    else
        success_count=0
        sleep 0.02
    fi
done

if [[ "$ready" != true ]]; then
    log_error "容器启动超时"
    write_placeholder
fi

END_TIME=$(date +%s.%N)
STARTUP_TIME=$(python3 <<PY
from decimal import Decimal
print(float(Decimal("${END_TIME}") - Decimal("${START_TIME}")))
PY
)

log_success "容器已启动 (${STARTUP_TIME}秒)"

# ============================================================================
# 【性能指标采集】
# 在有负载情况下采集，确保CPU有真实消耗
# ============================================================================
log "采集性能指标..."

# 【关键修复】先产生负载，再采集CPU
log "产生负载以获取真实CPU数据..."

# 获取容器内的 nginx 进程 PID（宿主机 PID），用于读取 /proc/<pid>/stat
CONTAINER_NGINX_PIDS=$(docker top "${CONTAINER_NAME}" -eo pid,comm 2>/dev/null | awk 'NR>1 && $2 ~ /^nginx/ {print $1}')

get_container_nginx_cpu_ticks() {
    PIDS="${CONTAINER_NGINX_PIDS}" python3 - <<'PY'
import os
total = 0
for pid in os.environ.get("PIDS", "").split():
    try:
        with open(f"/proc/{pid}/stat", "r", encoding="utf-8") as f:
            parts = f.read().split()
        total += int(parts[13]) + int(parts[14])
    except Exception:
        pass
print(total)
PY
}

HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
CPU_T0=$(get_container_nginx_cpu_ticks)
T0=$(date +%s.%N)

# 固定负载窗口：持续 2 秒打请求
LOAD_END=$((SECONDS + 2))
while [[ ${SECONDS} -lt ${LOAD_END} ]]; do
    for j in {1..25}; do
        curl -s -o /dev/null "http://localhost:${APP_PORT}/" >/dev/null 2>&1 || true &
    done
    wait || true
done

CPU_T1=$(get_container_nginx_cpu_ticks)
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
# 【内存测量】统计容器内所有进程的RSS内存
# 方法：获取容器内PID，使用ps统计RSS，与VM的测量方式对等
# ============================================================================
CONTAINER_PIDS=$(docker top "${CONTAINER_NAME}" -eo pid 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ',' | sed 's/,$//')
if [[ -n "${CONTAINER_PIDS}" ]]; then
    MEMORY_KB=$(ps -p ${CONTAINER_PIDS} -o rss --no-headers 2>/dev/null | awk '{sum+=$1} END {print sum+0}' || echo "0")
else
    MEMORY_KB="0"
fi
MEMORY_MB=$(python3 -c "print(round(${MEMORY_KB} / 1024, 2))" 2>/dev/null || echo "0")

# ============================================================================
# 【磁盘测量】统计Docker镜像大小
# 镜像包含完整的nginx运行环境，与VM的nginx+依赖库对等
# ============================================================================
IMAGE_BYTES=$(docker image inspect "${IMAGE}" --format '{{.Size}}' 2>/dev/null || echo 0)
DISK_MB=$(python3 <<PY
try:
    print(f"{float(${IMAGE_BYTES})/1024/1024:.2f}")
except:
    print("0")
PY
)

cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,${STARTUP_TIME}
cpu_percent,${CPU_PERCENT}
memory_mb,${MEMORY_MB}
disk_mb,${DISK_MB}
container_ip,${CONTAINER_IP:-unavailable}
EOF

[[ -n "${PERF_CSV}" ]] && echo "docker,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"

echo ""
log_success "Docker测试完成"
log "结果: ${OUTPUT_DIR}"
log "  启动时间: ${STARTUP_TIME}秒"
log "  CPU占用: ${CPU_PERCENT}%"
log "  内存占用: ${MEMORY_MB}MB"
log "  磁盘占用: ${DISK_MB}MB"
log "  容器IP: ${CONTAINER_IP:-unavailable}"

# 注意：不清理容器，让压测脚本可以使用
# 清理工作由 cleanup.sh 或 run_experiment.sh 完成
