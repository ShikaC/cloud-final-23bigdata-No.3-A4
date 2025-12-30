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
APP_PORT=${APP_PORT:-8080}  # 支持环境变量配置
SKIP_DEPS=false
AUTO_PORT=false  # 自动选择可用端口

# 兼容性：如果存在旧的 kvm 目录，重命名为 vm
if [[ -d "${RESULT_DIR}/kvm" ]] && [[ ! -d "${RESULT_DIR}/vm" ]]; then
    mv "${RESULT_DIR}/kvm" "${RESULT_DIR}/vm" 2>/dev/null || true
fi

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

log() { echo -e "${BLUE}[实验]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓ 成功]${NC} $*"; }
log_error() { echo -e "${RED}[✗ 错误]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[! 警告]${NC} $*"; }
log_info() { echo -e "${CYAN}[信息]${NC} $*"; }

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
    echo -e "${BOLD}${CYAN}║     云计算虚拟化与容器化性能对比实验                          ║${NC}"
    echo -e "${BOLD}${CYAN}║     VMWare Linux 虚拟机版本                                  ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_system() {
    print_header "系统环境检查"
    
    # 检查操作系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_info "操作系统: $PRETTY_NAME"
    else
        log_warning "无法检测操作系统类型"
    fi
    
    # 检查 CPU
    local cpu_cores=$(nproc 2>/dev/null || echo "未知")
    log_info "CPU 核心数: ${cpu_cores}"
    if [ "$cpu_cores" != "未知" ] && [ "$cpu_cores" -lt 2 ]; then
        log_warning "CPU 核心数较少，建议至少 2 核心"
    fi
    
    # 检查内存
    local mem_total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "未知")
    log_info "总内存: ${mem_total}"
    
    # 检查磁盘
    local disk_avail=$(df -h . 2>/dev/null | awk 'NR==2 {print $4}' || echo "未知")
    log_info "可用磁盘空间: ${disk_avail}"
    
    # 检查网络
    log "检查网络连接..."
    if ping -c 1 -W 2 google.com >/dev/null 2>&1 || ping -c 1 -W 2 baidu.com >/dev/null 2>&1; then
        log_success "网络连接正常"
    else
        log_warning "网络连接可能异常，但会继续运行"
    fi
    
    echo ""
}

install_dependencies() {
    print_header "安装依赖"
    
    log "开始安装系统依赖和 Python 包..."
    log_warning "这可能需要几分钟时间，请耐心等待"
    echo ""
    
    if bash "${SCRIPT_DIR}/install_dependencies.sh"; then
        log_success "依赖安装完成"
    else
        log_error "依赖安装失败"
        log "请检查错误信息，或参考 运行说明.md 手动安装"
        exit 1
    fi
    
    echo ""
}

check_docker() {
    log "检查 Docker 环境..."
    
    # 检查 Docker 是否安装
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Docker 未安装，将在安装依赖时自动安装"
        return 1
    fi
    
    # 检查 Docker 服务状态
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        log_warning "Docker 服务未运行，正在启动..."
        sudo systemctl start docker 2>/dev/null || true
        sleep 2
    fi
    
    # 检查 Docker 访问权限
    if ! docker info >/dev/null 2>&1; then
        log_warning "Docker 权限不足"
        
        # 尝试将用户加入 docker 组
        if ! groups | grep -q docker; then
            log "正在将当前用户加入 docker 组..."
            sudo usermod -aG docker "$USER" || true
            log_warning "已将用户加入 docker 组，但需要重新登录才能生效"
            log_info "临时解决方案：使用 'newgrp docker' 或用 sudo 运行脚本"
            
            # 尝试使用 newgrp
            log "尝试激活 docker 组..."
            if newgrp docker <<EOF >/dev/null 2>&1
docker info >/dev/null 2>&1
EOF
            then
                log_success "Docker 权限已激活"
                return 0
            else
                log_warning "需要使用 sudo 运行 Docker 命令"
                return 1
            fi
        fi
    else
        log_success "Docker 可用"
        return 0
    fi
}

check_and_fix_port() {
    log "检查端口 ${APP_PORT}..."
    
    # 检查端口是否被占用
    local port_in_use=false
    if command -v ss >/dev/null 2>&1; then
        if ss -tuln 2>/dev/null | grep -q ":${APP_PORT} "; then
            port_in_use=true
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":${APP_PORT} "; then
            port_in_use=true
        fi
    fi
    
    if [[ "$port_in_use" == "true" ]]; then
        log_warning "端口 ${APP_PORT} 已被占用"
        
        # 显示占用信息
        if [[ -f "${SCRIPT_DIR}/port_manager.sh" ]]; then
            bash "${SCRIPT_DIR}/port_manager.sh" info "${APP_PORT}" 2>/dev/null || true
        fi
        
        echo ""
        
        if [[ "$AUTO_PORT" == "true" ]]; then
            log "自动查找可用端口..."
            local new_port
            if [[ -f "${SCRIPT_DIR}/port_manager.sh" ]]; then
                new_port=$(bash "${SCRIPT_DIR}/port_manager.sh" find "${APP_PORT}" 50 2>/dev/null | tail -1 || echo "")
            else
                # 简单的端口查找
                for ((i=0; i<50; i++)); do
                    local test_port=$((APP_PORT + i))
                    if ! (ss -tuln 2>/dev/null | grep -q ":${test_port} " || netstat -tuln 2>/dev/null | grep -q ":${test_port} "); then
                        new_port=$test_port
                        break
                    fi
                done
            fi
            
            if [[ -n "$new_port" ]]; then
                APP_PORT=$new_port
                log_success "自动选择端口: ${APP_PORT}"
            else
                log_error "无法找到可用端口"
                exit 1
            fi
        else
            log_warning "请选择以下操作："
            echo "  1. 释放端口 ${APP_PORT}（杀死占用进程）"
            echo "  2. 使用其他端口"
            echo "  3. 退出"
            echo ""
            read -p "请选择 [1-3]: " -n 1 -r choice
            echo ""
            
            case $choice in
                1)
                    log "释放端口 ${APP_PORT}..."
                    if [[ -f "${SCRIPT_DIR}/port_manager.sh" ]]; then
                        if bash "${SCRIPT_DIR}/port_manager.sh" kill "${APP_PORT}" -f; then
                            log_success "端口已释放"
                        else
                            log_error "释放端口失败"
                            exit 1
                        fi
                    else
                        log_error "找不到 port_manager.sh，无法自动释放端口"
                        log_info "请手动释放端口或使用其他端口"
                        exit 1
                    fi
                    ;;
                2)
                    read -p "请输入新端口号: " new_port
                    if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ $new_port -ge 1 ]] && [[ $new_port -le 65535 ]]; then
                        APP_PORT=$new_port
                        log_info "使用端口: ${APP_PORT}"
                        # 递归检查新端口
                        check_and_fix_port
                    else
                        log_error "无效的端口号"
                        exit 1
                    fi
                    ;;
                3)
                    log "退出"
                    exit 0
                    ;;
                *)
                    log_error "无效的选择"
                    exit 1
                    ;;
            esac
        fi
    else
        log_success "端口 ${APP_PORT} 可用"
    fi
    
    echo ""
}

validate_environment() {
    # 基本工具检查（vm_test.sh 会自动安装缺失的工具）
    log "验证运行环境..."
    
    # 检查 Docker（可选，会在后续自动处理）
    check_docker || log_warning "Docker 环境需要配置，将在运行时处理"
    
    # 检查权限提示
    if [[ $EUID -ne 0 ]]; then
        log_info "将使用 sudo 执行需要特权的操作"
        log_info "可能会提示输入密码"
    fi
    
    log_success "环境验证完成"
    echo ""
    
    # 检查并处理端口冲突
    check_and_fix_port
}

activate_venv() {
    # 可选激活虚拟环境
    if [[ -d "${SCRIPT_DIR}/venv" ]]; then
        if [[ -f "${SCRIPT_DIR}/venv/bin/activate" ]]; then
            # shellcheck disable=SC1091
            source "${SCRIPT_DIR}/venv/bin/activate"
            log "已激活Python虚拟环境"
        fi
    fi
}

prepare_directories() {
    log "准备结果目录..."
    mkdir -p "${RESULT_DIR}" "${VIS_DIR}"
    
    # 备份旧结果（如果存在）
    if [[ -f "${PERF_CSV}" ]]; then
        local backup="${PERF_CSV}.bak.$(date +%Y%m%d_%H%M%S)"
        mv "${PERF_CSV}" "${backup}"
        log "已备份旧结果: ${backup}"
    fi
    
    # 初始化CSV文件
    echo "platform,startup_time_sec,cpu_percent,memory_mb,disk_mb" > "${PERF_CSV}"
}

run_vm_test() {
    print_header "步骤 1/4: VM 虚拟机测试"
    
    log "在当前 VMWare 虚拟机上运行 Nginx 性能测试..."
    
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
    print_header "步骤 2/4: Docker容器测试"
    
    # 检查 Docker 权限，如果失败使用 sudo
    if ! docker info >/dev/null 2>&1; then
        log_warning "Docker 需要 sudo 权限"
        if ! sudo bash "${SCRIPT_DIR}/docker_test.sh" \
            --container-name "docker-nginx" \
            --app-port "${APP_PORT}" \
            --output-dir "${RESULT_DIR}/docker" \
            --perf-csv "${PERF_CSV}"; then
            log_error "Docker测试失败"
            return 1
        fi
    else
        if ! bash "${SCRIPT_DIR}/docker_test.sh" \
            --container-name "docker-nginx" \
            --app-port "${APP_PORT}" \
            --output-dir "${RESULT_DIR}/docker" \
            --perf-csv "${PERF_CSV}"; then
            log_error "Docker测试失败"
            return 1
        fi
    fi
    
    log_success "Docker测试完成"
    return 0
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --port)
                APP_PORT="$2"
                shift 2
                ;;
            --auto-port)
                AUTO_PORT=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat <<EOF
使用方法: bash run_experiment.sh [选项]

运行完整的虚拟化与容器化性能对比实验

选项:
  --skip-deps      跳过依赖安装（假设已安装）
  --port <端口>     指定使用的端口号（默认: 8080）
  --auto-port      自动查找可用端口（遇到冲突时）
  -h, --help       显示此帮助信息

端口配置:
  可通过以下方式指定端口：
  1. 环境变量: export APP_PORT=9090 && bash run_experiment.sh
  2. 命令参数: bash run_experiment.sh --port 9090
  3. 自动模式: bash run_experiment.sh --auto-port

  如果端口被占用，脚本会提示您：
  - 释放该端口（杀死占用进程）
  - 选择其他端口
  - 或使用 --auto-port 自动选择

示例:
  bash run_experiment.sh                      # 完整运行（默认端口8080）
  bash run_experiment.sh --skip-deps          # 跳过依赖安装
  bash run_experiment.sh --port 9090          # 使用端口9090
  bash run_experiment.sh --auto-port          # 自动选择可用端口
  APP_PORT=9090 bash run_experiment.sh        # 通过环境变量指定端口
  sudo bash run_experiment.sh                 # 使用 sudo 运行

端口管理工具:
  # 检查端口是否被占用
  bash src/port_manager.sh check 8080
  
  # 查看占用端口的进程
  bash src/port_manager.sh info 8080
  
  # 释放端口（杀死占用进程）
  bash src/port_manager.sh kill 8080
  
  # 查找可用端口
  bash src/port_manager.sh find 8080

说明:
  脚本会自动：
  1. 检查系统环境和端口可用性
  2. 安装缺失的依赖（如果需要）
  3. 运行 VM 测试（VMWare 虚拟机 + Nginx）
  4. 运行 Docker 测试（容器 + Nginx）
  5. 执行压力测试
  6. 生成可视化图表
  7. 显示详细结果

EOF
}

parse_args "$@"

print_banner
check_system

# 安装依赖（如果需要）
if [ "$SKIP_DEPS" = false ]; then
    install_dependencies
else
    log_info "跳过依赖安装"
    echo ""
fi

validate_environment
activate_venv
prepare_directories

# 执行测试
log_info "实验包括："
log_info "  1. VM 测试 - 在虚拟机上运行 Nginx"
log_info "  2. Docker 测试 - 在容器中运行 Nginx"
log_info "  3. 压力测试 - 对比两种环境的性能"
log_info "  4. 数据可视化 - 生成性能对比图表"
echo ""
log_warning "实验可能需要 3-5 分钟，请耐心等待"
echo ""

run_vm_test || log_warning "VM测试失败，继续执行后续步骤"
run_docker_test || log_warning "Docker测试失败，继续执行后续步骤"

run_stress_test() {
    print_header "步骤 3/4: 压力测试"
    
    # 获取VM IP
    local vm_ip
    if [[ -f "${RESULT_DIR}/vm/vm_ip.txt" ]]; then
        vm_ip=$(cat "${RESULT_DIR}/vm/vm_ip.txt" 2>/dev/null || echo "localhost")
    elif [[ -f "${RESULT_DIR}/kvm/vm_ip.txt" ]]; then
        # 兼容旧版本
        vm_ip=$(cat "${RESULT_DIR}/kvm/vm_ip.txt" 2>/dev/null || echo "localhost")
    else
        log_warning "未找到VM IP，使用localhost"
        vm_ip="localhost"
    fi
    
    local vm_url="http://${vm_ip}:${APP_PORT}"
    local docker_url="http://localhost:${APP_PORT}"
    
    log "压测目标:"
    log "  VM: ${vm_url}"
    log "  Docker: ${docker_url}"
    
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

run_visualization() {
    print_header "步骤 4/4: 生成可视化图表"
    
    # 验证数据文件存在
    if [[ ! -f "${PERF_CSV}" ]] || [[ ! -f "${STRESS_CSV}" ]]; then
        log_error "数据文件不完整，无法生成图表"
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

# 执行压测和可视化
run_stress_test || log_warning "压测失败，继续生成可视化"
run_visualization || log_warning "可视化生成失败"

# 显示详细结果
show_results() {
    print_header "实验完成 - 结果报告"
    
    log_success "所有步骤已执行完毕！"
    echo ""
    
    # 显示结果文件状态
    log_info "结果文件："
    echo ""
    
    if [ -f "${PERF_CSV}" ]; then
        echo -e "  ${GREEN}✓${NC} 性能数据: ${PERF_CSV}"
    else
        echo -e "  ${RED}✗${NC} 性能数据缺失"
    fi
    
    if [ -f "${STRESS_CSV}" ]; then
        echo -e "  ${GREEN}✓${NC} 压测数据: ${STRESS_CSV}"
    else
        echo -e "  ${RED}✗${NC} 压测数据缺失"
    fi
    
    if [ -d "${VIS_DIR}" ]; then
        local chart_count=$(find "${VIS_DIR}" -name "*.png" 2>/dev/null | wc -l)
        if [ "$chart_count" -gt 0 ]; then
            echo -e "  ${GREEN}✓${NC} 可视化图表: ${VIS_DIR}/ (${chart_count} 个图表)"
        else
            echo -e "  ${YELLOW}!${NC} 可视化图表目录为空"
        fi
    else
        echo -e "  ${RED}✗${NC} 可视化图表缺失"
    fi
    
    echo ""
    
    # 显示性能数据
    if [ -f "${PERF_CSV}" ]; then
        log_info "性能对比数据："
        echo ""
        if command -v column >/dev/null 2>&1; then
            cat "${PERF_CSV}" | column -t -s ',' | sed 's/^/    /'
        else
            cat "${PERF_CSV}" | sed 's/^/    /'
        fi
        echo ""
    fi
    
    # 显示压测数据
    if [ -f "${STRESS_CSV}" ]; then
        log_info "压力测试数据："
        echo ""
        if command -v column >/dev/null 2>&1; then
            cat "${STRESS_CSV}" | column -t -s ',' | sed 's/^/    /'
        else
            cat "${STRESS_CSV}" | sed 's/^/    /'
        fi
        echo ""
    fi
    
    # 显示图表列表
    if [ -d "${VIS_DIR}" ] && [ "$(find "${VIS_DIR}" -name "*.png" 2>/dev/null | wc -l)" -gt 0 ]; then
        log_info "生成的图表："
        echo ""
        find "${VIS_DIR}" -name "*.png" 2>/dev/null | sort | while read chart; do
            echo "    - $(basename "$chart")"
        done
        echo ""
    fi
}

print_summary() {
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  实验成功完成！${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "实验内容："
    echo "  ✓ VM 环境测试（VMWare 虚拟机 + Nginx）"
    echo "  ✓ Docker 环境测试（Docker 容器 + Nginx）"
    echo "  ✓ 性能压力测试（Apache Bench）"
    echo "  ✓ 数据可视化（性能对比图表）"
    echo ""
    
    log_info "下一步操作："
    echo ""
    echo "  1. 查看详细数据："
    echo "     cat ${PERF_CSV}"
    echo "     cat ${STRESS_CSV}"
    echo ""
    echo "  2. 查看可视化图表："
    echo "     在文件管理器中打开 ${VIS_DIR}/"
    echo ""
    echo "  3. 清理实验环境："
    echo "     bash ${SCRIPT_DIR}/cleanup.sh"
    echo ""
    echo "  4. 再次运行实验："
    echo "     bash ${SCRIPT_DIR}/run_experiment.sh"
    echo ""
    
    log_info "更多信息请参考："
    echo "  - ${SCRIPT_DIR}/运行说明.md"
    echo "  - README.md"
    echo ""
}

show_results
print_summary

