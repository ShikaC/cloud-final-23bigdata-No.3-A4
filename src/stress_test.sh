#!/bin/bash
# =============================================================================
# 精简版压测脚本（Apache Bench）
# 输出统一的 stress.csv：platform,qps,avg_latency_ms,failed,transfer_kbps
# =============================================================================

set -euo pipefail

VM_URL="http://localhost:8080"
DOCKER_URL="http://localhost:8080"
TOTAL_REQUESTS=2000
CONCURRENCY=50
OUTPUT_DIR="./results"
OUTPUT_CSV="./results/stress.csv"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm-url) VM_URL="$2"; shift 2;;
        --docker-url) DOCKER_URL="$2"; shift 2;;
        --requests) TOTAL_REQUESTS="$2"; shift 2;;
        --concurrency) CONCURRENCY="$2"; shift 2;;
        --output-dir) OUTPUT_DIR="$2"; shift 2;;
        --output-csv) OUTPUT_CSV="$2"; shift 2;;
        *) echo "未知参数: $1"; exit 1;;
    esac
done

mkdir -p "${OUTPUT_DIR}"
echo "platform,qps,avg_latency_ms,failed,transfer_kbps" > "${OUTPUT_CSV}"

log() { echo -e "[压测] $*"; }

write_placeholder() {
    echo "kvm,0,0,0,0" >> "${OUTPUT_CSV}"
    echo "docker,0,0,0,0" >> "${OUTPUT_CSV}"
    exit 0
}

command -v ab >/dev/null 2>&1 || {
    log "未找到 ab，写入占位结果"
    write_placeholder
}

run_ab() {
    local name=$1
    local url=$2
    local outfile="${OUTPUT_DIR}/stress_${name}.txt"

    log "开始压测 ${name}: ${url}"
    if ! curl -s -o /dev/null -w "%{http_code}" "${url}" | grep -q "200"; then
        log "${name} 无法访问，记录为0"
        echo "${name},0,0,0,0" >> "${OUTPUT_CSV}"
        return
    fi

    if ! ab -n "${TOTAL_REQUESTS}" -c "${CONCURRENCY}" -q "${url}/" > "${outfile}" 2>&1; then
        log "${name} 压测失败，记录为0"
        echo "${name},0,0,0,0" >> "${OUTPUT_CSV}"
        return
    fi

    local qps=$(grep "Requests per second" "${outfile}" | awk '{print $4}')
    local avg=$(grep "Time per request" "${outfile}" | head -1 | awk '{print $4}')
    local failed=$(grep "Failed requests" "${outfile}" | awk '{print $3}' | head -1)
    local transfer=$(grep "Transfer rate" "${outfile}" | awk '{print $3}')

    echo "${name},${qps:-0},${avg:-0},${failed:-0},${transfer:-0}" >> "${OUTPUT_CSV}"
    log "${name} 完成，QPS=${qps:-0}, 平均延迟=${avg:-0}ms"
}

run_ab "kvm" "${VM_URL}"
run_ab "docker" "${DOCKER_URL}"

log "压测完成，结果写入 ${OUTPUT_CSV}"

