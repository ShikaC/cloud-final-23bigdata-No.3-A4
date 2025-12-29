#!/bin/bash
# =============================================================================
# 题目4精简版一键脚本
# - 运行 KVM 与 Docker 的 Nginx 部署与性能采集
# - 输出统一的 performance.csv 与 stress.csv
# - 生成可视化图表到 results/visualization
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_DIR="${SCRIPT_DIR}/results"
VIS_DIR="${RESULT_DIR}/visualization"
PERF_CSV="${RESULT_DIR}/performance.csv"
STRESS_CSV="${RESULT_DIR}/stress.csv"
APP_PORT=8080

log() { echo -e "[RUN] $*"; }

# 可选激活虚拟环境
if [[ -d "${SCRIPT_DIR}/venv" ]]; then
    # shellcheck disable=SC1091
    source "${SCRIPT_DIR}/venv/bin/activate"
fi

mkdir -p "${RESULT_DIR}" "${VIS_DIR}"
rm -f "${PERF_CSV}" "${STRESS_CSV}"
echo "platform,startup_time_sec,cpu_percent,memory_mb,disk_mb" > "${PERF_CSV}"

log "执行 KVM 测试..."
bash "${SCRIPT_DIR}/vm_test.sh" \
    --vm-name "kvm-nginx" \
    --app-port "${APP_PORT}" \
    --output-dir "${RESULT_DIR}/kvm" \
    --perf-csv "${PERF_CSV}"

log "执行 Docker 测试..."
bash "${SCRIPT_DIR}/docker_test.sh" \
    --container-name "docker-nginx" \
    --app-port "${APP_PORT}" \
    --output-dir "${RESULT_DIR}/docker" \
    --perf-csv "${PERF_CSV}"

VM_IP=$(cat "${RESULT_DIR}/kvm/vm_ip.txt" 2>/dev/null || echo "localhost")
VM_URL="http://${VM_IP}:${APP_PORT}"
DOCKER_URL="http://localhost:${APP_PORT}"

log "执行压测..."
bash "${SCRIPT_DIR}/stress_test.sh" \
    --vm-url "${VM_URL}" \
    --docker-url "${DOCKER_URL}" \
    --requests 2000 \
    --concurrency 50 \
    --output-dir "${RESULT_DIR}" \
    --output-csv "${STRESS_CSV}"

log "生成可视化..."
python3 "${SCRIPT_DIR}/visualize_results.py" \
    --performance-csv "${PERF_CSV}" \
    --stress-csv "${STRESS_CSV}" \
    --output-dir "${VIS_DIR}"

log "完成！"
log "性能数据: ${PERF_CSV}"
log "压测数据: ${STRESS_CSV}"
log "图表目录: ${VIS_DIR}"

