#!/bin/bash
# =============================================================================
# 虚拟化与容器化性能对比实验 - 一键运行脚本
# =============================================================================
# 功能：
#   - 系统环境检查
#   - 运行 VM 与 Docker 的 Nginx 部署与性能采集
#   - 执行压力测试
#   - 输出统一的 performance.csv 与 stress.csv
#   - 生成可视化图表到 results/visualization
#   - 显示详细的结果报告
#
# 使用方法:
#   bash run_experiment.sh              # 完整流程（包含依赖安装）
#   bash run_experiment.sh --skip-deps  # 跳过依赖安装
#
# 要求：
#   - Ubuntu/Debian/CentOS 等 Linux 系统
#   - 需要 sudo 权限
#   - 需要网络连接（首次运行）
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_DIR="${SCRIPT_DIR}/results"
VIS_DIR="${RESULT_DIR}/visualization"
PERF_CSV="${RESULT_DIR}/performance.csv"
STRESS_CSV="${RESULT_DIR}/stress.csv"
APP_PORT=${APP_PORT:-8080}
SKIP_DEPS=false
AUTO_PORT=false

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[实验]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
log_info() { echo -e "${CYAN}[i]${NC} $*"; }

print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
    echo -e "${BOLD}${CYAN}║     云计算虚拟化与容器化性能对比实验                          ║${NC}"
    echo -e "${BOLD}${CYAN}║     VM vs Docker 性能测试                                    ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_and_fix_port() {
    log "检查端口 ${APP_PORT}..."
    
    if bash "${SCRIPT_DIR}/port_manager.sh" check "${APP_PORT}" >/dev/null 2>&1; then
        log_success "端口 ${APP_PORT} 可用"
    else
        log_warning "端口 ${APP_PORT} 已被占用"
        
        if [[ "$AUTO_PORT" == "true" ]]; then
            APP_PORT=$(bash "${SCRIPT_DIR}/port_manager.sh" find "${APP_PORT}" | tail -n 1)
            log_success "自动选择端口: ${APP_PORT}"
        else
            log_warning "请选择操作："
            echo "  1. 使用其他端口"
            echo "  2. 强制释放端口 (需要 sudo)"
            echo "  3. 退出"
            read -p "请选择 [1-3]: " -n 1 -r choice
            echo ""
            
            case $choice in
                1)
                    read -p "请输入新端口号: " new_port
                    if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ $new_port -ge 1024 ]] && [[ $new_port -le 65535 ]]; then
                        APP_PORT=$new_port
                        check_and_fix_port
                    else
                        log_error "无效的端口号"
                        exit 1
                    fi
                    ;;
                2)
                    if sudo bash "${SCRIPT_DIR}/port_manager.sh" kill "${APP_PORT}" -f; then
                        log_success "端口已释放"
                        check_and_fix_port
                    else
                        log_error "无法释放端口"
                        exit 1
                    fi
                    ;;
                3)
                    exit 0
                    ;;
                *)
                    log_error "无效的选择"
                    exit 1
                    ;;
            esac
        fi
    fi
}

install_dependencies() {
    log "安装依赖..."
    if bash "${SCRIPT_DIR}/install_dependencies.sh"; then
        log_success "依赖安装完成"
    else
        log_error "依赖安装失败"
        exit 1
    fi
}

activate_venv() {
    if [[ -d "${SCRIPT_DIR}/venv" && -f "${SCRIPT_DIR}/venv/bin/activate" ]]; then
        source "${SCRIPT_DIR}/venv/bin/activate"
        log "已激活Python虚拟环境"
    fi
}

prepare_directories() {
    log "准备结果目录..."
    mkdir -p "${RESULT_DIR}" "${VIS_DIR}"
    
    if [[ -f "${PERF_CSV}" ]]; then
        local backup="${PERF_CSV}.bak.$(date +%Y%m%d_%H%M%S)"
        mv "${PERF_CSV}" "${backup}"
        log "已备份旧结果"
    fi
    
    echo "platform,startup_time_sec,cpu_percent,memory_mb,disk_mb" > "${PERF_CSV}"
}

run_vm_test() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 1/4: VM 虚拟机测试 ━━━━${NC}"
    echo ""
    
    if ! bash "${SCRIPT_DIR}/vm_test.sh" \
        --vm-name "vmware-nginx" \
        --app-port "${APP_PORT}" \
        --output-dir "${RESULT_DIR}/vm" \
        --perf-csv "${PERF_CSV}"; then
        log_error "VM测试失败"
        return 1
    fi
    
    log_success "VM测试完成"
    return 0
}

run_docker_test() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 2/4: Docker容器测试 ━━━━${NC}"
    echo ""
    
    if ! docker info >/dev/null 2>&1; then
        log_warning "Docker需要sudo权限"
        sudo bash "${SCRIPT_DIR}/docker_test.sh" \
            --container-name "docker-nginx" \
            --app-port "${APP_PORT}" \
            --output-dir "${RESULT_DIR}/docker" \
            --perf-csv "${PERF_CSV}" || return 1
    else
        bash "${SCRIPT_DIR}/docker_test.sh" \
            --container-name "docker-nginx" \
            --app-port "${APP_PORT}" \
            --output-dir "${RESULT_DIR}/docker" \
            --perf-csv "${PERF_CSV}" || return 1
    fi
    
    log_success "Docker测试完成"
    return 0
}

run_stress_test() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 3/4: 压力测试 ━━━━${NC}"
    echo ""
    
    local vm_ip="localhost"
    [[ -f "${RESULT_DIR}/vm/vm_ip.txt" ]] && vm_ip=$(cat "${RESULT_DIR}/vm/vm_ip.txt")
    
    local vm_url="http://${vm_ip}:${APP_PORT}"
    local docker_url="http://localhost:${APP_PORT}"
    
    log "压测目标: VM=${vm_url}, Docker=${docker_url}"
    
    if ! bash "${SCRIPT_DIR}/stress_test.sh" \
        --vm-url "${vm_url}" \
        --docker-url "${docker_url}" \
        --requests 2000 \
        --concurrency 50 \
        --output-dir "${RESULT_DIR}" \
        --output-csv "${STRESS_CSV}"; then
        log_error "压测失败"
        return 1
    fi
    
    log_success "压测完成"
    return 0
}

run_analysis() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 4/5: 生成分析报告 ━━━━${NC}"
    echo ""
    
    if ! python3 "${SCRIPT_DIR}/analyze_results.py" \
        --vm-dir "${RESULT_DIR}/vm" \
        --docker-dir "${RESULT_DIR}/docker" \
        --stress-dir "${RESULT_DIR}" \
        --output-file "${RESULT_DIR}/analysis_report.md"; then
        log_error "分析报告生成失败"
        return 1
    fi
    
    log_success "分析报告已生成: ${RESULT_DIR}/analysis_report.md"
    return 0
}

run_visualization() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 5/5: 生成可视化图表 ━━━━${NC}"
    echo ""
    
    if [[ ! -f "${PERF_CSV}" ]] || [[ ! -f "${STRESS_CSV}" ]]; then
        log_error "数据文件不完整"
        return 1
    fi
    
    if ! python3 "${SCRIPT_DIR}/visualize_results.py" \
        --performance-csv "${PERF_CSV}" \
        --stress-csv "${STRESS_CSV}" \
        --output-dir "${VIS_DIR}"; then
        log_error "可视化生成失败"
        return 1
    fi
    
    log_success "可视化图表已生成"
    return 0
}

fix_permissions() {
    log "优化结果文件权限..."
    # 确保所有结果文件对当前用户及其组可见 (644)，目录可进入 (755)
    # 使用 a+rX 是一种简单有效的方式
    if [[ -d "${RESULT_DIR}" ]]; then
        chmod -R a+rX "${RESULT_DIR}" 2>/dev/null || true
        
        # 如果当前是以 sudo 运行，将结果文件夹的所有权交还给原始用户
        if [[ -n "${SUDO_USER:-}" ]]; then
            local real_user="${SUDO_USER}"
            local real_group=$(id -gn "${SUDO_USER}" 2>/dev/null || echo "${SUDO_USER}")
            chown -R "${real_user}:${real_group}" "${RESULT_DIR}" 2>/dev/null || true
        fi
    fi
}

show_results() {
    fix_permissions
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  实验完成！${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    log_info "结果文件："
    echo "  ✓ 性能数据: ${PERF_CSV}"
    echo "  ✓ 压测数据: ${STRESS_CSV}"
    echo "  ✓ 分析报告: ${RESULT_DIR}/analysis_report.md"
    echo "  ✓ 图表目录: ${VIS_DIR}/"
    echo ""
    
    if [[ -f "${PERF_CSV}" ]]; then
        log_info "性能对比："
        column -t -s ',' "${PERF_CSV}" 2>/dev/null | sed 's/^/  /' || cat "${PERF_CSV}" | sed 's/^/  /'
        echo ""
    fi
    
    log_info "下一步："
    echo "  • 查看图表: cd ${VIS_DIR}"
    echo "  • 清理环境: bash ${SCRIPT_DIR}/cleanup.sh"
    echo "  • 再次运行: bash $0"
    echo ""
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-deps) SKIP_DEPS=true; shift ;;
            --port) APP_PORT="$2"; shift 2 ;;
            --auto-port) AUTO_PORT=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; show_help; exit 1 ;;
        esac
    done
}

show_help() {
    cat <<EOF
使用方法: bash run_experiment.sh [选项]

选项:
  --skip-deps      跳过依赖安装
  --port <端口>     指定使用的端口号（默认: 8080）
  --auto-port      自动查找可用端口
  -h, --help       显示此帮助信息

示例:
  bash run_experiment.sh                    # 完整运行
  bash run_experiment.sh --skip-deps        # 跳过依赖安装
  bash run_experiment.sh --port 9090        # 使用端口9090
  bash run_experiment.sh --auto-port        # 自动选择端口
  APP_PORT=9090 bash run_experiment.sh      # 通过环境变量设置端口
EOF
}

parse_args "$@"

print_banner

if [ "$SKIP_DEPS" = false ]; then
    install_dependencies
else
    log_info "跳过依赖安装"
fi

check_and_fix_port
activate_venv
prepare_directories

run_vm_test || log_warning "VM测试失败"

# 等待系统稳定，确保测试公平性
log "等待系统稳定..."
sleep 2

run_docker_test || log_warning "Docker测试失败"

# 等待系统稳定，确保测试公平性
log "等待系统稳定..."
sleep 2

run_stress_test || log_warning "压测失败"
run_analysis || log_warning "分析失败"
run_visualization || log_warning "可视化失败"

show_results
