#!/bin/bash
# =============================================================================
# 精简版压测脚本（Apache Bench）
# =============================================================================
# 功能：使用Apache Bench对VM和Docker进行压力测试
# 输出：stress.csv (格式: platform,qps,avg_latency_ms,failed,transfer_kbps)
#
# 使用方法:
#   bash stress_test.sh --vm-url http://VM_IP:8080 --docker-url http://localhost:80
# =============================================================================

set -euo pipefail

VM_URL="http://localhost:8080"
DOCKER_URL="http://localhost:80"
TOTAL_REQUESTS=10000
CONCURRENCY=1000
OUTPUT_DIR="./results"
OUTPUT_CSV="./results/stress.csv"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[压测]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }

write_placeholder() {
    log_warning "生成占位数据"
    echo "platform,qps,avg_latency_ms,failed,transfer_kbps" > "${OUTPUT_CSV}"
    echo "vm,0,0,0,0" >> "${OUTPUT_CSV}"
    echo "docker,0,0,0,0" >> "${OUTPUT_CSV}"
    exit 0
}

validate_dependencies() {
    local missing=()
    command -v ab >/dev/null 2>&1 || missing+=("ab")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少工具: ${missing[*]}"
        log "请安装: sudo apt-get install apache2-utils curl"
        write_placeholder
    fi
}

check_url_accessible() {
    local url="$1"
    for ((i=1; i<=3; i++)); do
        curl -s -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null | grep -q "200" && return 0
        [[ $i -lt 3 ]] && sleep 2
    done
    return 1
}

extract_ab_metrics() {
    local outfile="$1"
    local qps=$(grep "Requests per second" "${outfile}" 2>/dev/null | awk '{print $4}' | head -1)
    local avg=$(grep "Time per request" "${outfile}" 2>/dev/null | head -1 | awk '{print $4}' | head -1)
    local failed=$(grep "Failed requests" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
    local transfer=$(grep "Transfer rate" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
    echo "${qps:-0},${avg:-0},${failed:-0},${transfer:-0}"
}

run_ab() {
    local name=$1
    local url=$2
    local outfile="${OUTPUT_DIR}/stress_${name}.txt"

    log "压测 ${name}: ${url}"
    
    if ! check_url_accessible "${url}"; then
        log_error "${name} 无法访问"
        echo "${name},0,0,0,0" >> "${OUTPUT_CSV}"
        return 1
    fi
    
    # 预热：发送少量请求让服务稳定
    log "预热 ${name}..."
    ab -n 100 -c 10 -q "${url}/" > /dev/null 2>&1 || true
    sleep 2
    
    # 正式压测：确保两种模式使用完全相同的参数
    # 添加 -k (Keep-Alive) 以测试真实吞吐量
    log "正式压测 ${name}..."
    ulimit -n 65535 >/dev/null 2>&1 || true
    if ! ab -n "${TOTAL_REQUESTS}" -c "${CONCURRENCY}" -k -q "${url}/" > "${outfile}" 2>&1; then
        log_error "${name} 压测失败"
        echo "${name},0,0,0,0" >> "${OUTPUT_CSV}"
        return 1
    fi
    
    local metrics=$(extract_ab_metrics "${outfile}")
    echo "${name},${metrics}" >> "${OUTPUT_CSV}"
    
    local qps=$(echo "$metrics" | cut -d',' -f1)
    local avg=$(echo "$metrics" | cut -d',' -f2)
    
    log_success "${name} 完成: QPS=${qps}, 延迟=${avg}ms"
    return 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm-url) VM_URL="$2"; shift 2;;
            --docker-url) DOCKER_URL="$2"; shift 2;;
            --requests) TOTAL_REQUESTS="$2"; shift 2;;
            --concurrency) CONCURRENCY="$2"; shift 2;;
            --output-dir) OUTPUT_DIR="$2"; shift 2;;
            --output-csv) OUTPUT_CSV="$2"; shift 2;;
            *) log_error "未知参数: $1"; exit 1;;
        esac
    done
}

parse_args "$@"
mkdir -p "${OUTPUT_DIR}"
echo "platform,qps,avg_latency_ms,failed,transfer_kbps" > "${OUTPUT_CSV}"

validate_dependencies

log "配置: 请求=${TOTAL_REQUESTS}, 并发=${CONCURRENCY}"
log "目标: VM=${VM_URL}, Docker=${DOCKER_URL}"
echo ""

run_ab "vm" "${VM_URL}"
echo ""
run_ab "docker" "${DOCKER_URL}"

echo ""
log_success "压测完成: ${OUTPUT_CSV}"
