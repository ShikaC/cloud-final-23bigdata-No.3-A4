#!/bin/bash
# =============================================================================
# 精简版 Docker Nginx 部署与性能采集脚本
# 关注：启动时间、CPU占用、内存占用、磁盘占用，输出CSV
# =============================================================================

set -euo pipefail

CONTAINER_NAME="docker-nginx"
APP_PORT=8080
OUTPUT_DIR="./results/docker"
PERF_CSV=""
IMAGE="nginx:alpine"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --container-name) CONTAINER_NAME="$2"; shift 2;;
        --app-port) APP_PORT="$2"; shift 2;;
        --output-dir) OUTPUT_DIR="$2"; shift 2;;
        --perf-csv) PERF_CSV="$2"; shift 2;;
        --image) IMAGE="$2"; shift 2;;
        *) echo "未知参数: $1"; exit 1;;
    esac
done

mkdir -p "${OUTPUT_DIR}"

log() { echo -e "[Docker] $*"; }

write_placeholder() {
    log "缺少Docker，生成占位数据"
    cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,0
cpu_percent,0
memory_mb,0
disk_mb,0
container_ip,unavailable
EOF
    if [[ -n "${PERF_CSV}" ]]; then
        echo "docker,0,0,0,0" >> "${PERF_CSV}"
    fi
    exit 0
}

command -v docker >/dev/null 2>&1 || write_placeholder

# 清理旧容器
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

log "拉取镜像 ${IMAGE}..."
docker pull "${IMAGE}" >/dev/null

log "启动容器并测量启动时间..."
START_TIME=$(date +%s.%N)
docker run -d --name "${CONTAINER_NAME}" -p "${APP_PORT}:80" "${IMAGE}" >/dev/null

# 等待就绪
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")
for _ in {1..30}; do
    if curl -s "http://localhost:${APP_PORT}" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
END_TIME=$(date +%s.%N)
STARTUP_TIME=$(python3 - <<PY
from decimal import Decimal
print(Decimal("${END_TIME}") - Decimal("${START_TIME}"))
PY
)

# 采集指标
STATS=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" "${CONTAINER_NAME}" | head -1)
CPU_PERCENT=$(echo "${STATS}" | cut -d',' -f1 | tr -d '%')
MEM_USAGE_RAW=$(echo "${STATS}" | cut -d',' -f2)
MEMORY_MB=$(python3 - <<PY
import re,sys
raw="${MEM_USAGE_RAW}"
used = raw.split('/')[0].strip() if '/' in raw else raw
num = float(re.sub('[^0-9.]','', used) or 0)
if 'GiB' in used or 'GB' in used: num *= 1024
print(f"{num:.2f}")
PY
)

IMAGE_BYTES=$(docker image inspect "${IMAGE}" --format '{{.Size}}' 2>/dev/null || echo 0)
CONTAINER_BYTES=$(docker container inspect --size "${CONTAINER_NAME}" --format '{{.SizeRootFs}}' 2>/dev/null || echo 0)
DISK_BYTES=$(python3 - <<PY
try:
    img=int("${IMAGE_BYTES}")
    cnt=int("${CONTAINER_BYTES}")
    print(img+cnt)
except Exception:
    print(0)
PY
)
DISK_MB=$(python3 - <<PY
try:
    print(f"{float(${DISK_BYTES})/1024/1024:.2f}")
except Exception:
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

if [[ -n "${PERF_CSV}" ]]; then
    echo "docker,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"
fi

log "完成，数据已写入 ${OUTPUT_DIR}"

