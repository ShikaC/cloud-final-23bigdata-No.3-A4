#!/bin/bash
# =============================================================================
# 依赖安装脚本
# =============================================================================
# 功能说明：
#   自动检测系统类型并安装实验所需的所有依赖
#
# 使用方法：
#   bash install_dependencies.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/venv"

readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[安装]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    log "操作系统: $OS"
}

install_ubuntu_deps() {
    log "更新软件包列表..."
    sudo apt-get update -qq
    
    log "安装系统依赖..."
    sudo apt-get install -y nginx docker.io apache2-utils \
        python3 python3-pip python3-venv \
        curl wget bc net-tools >/dev/null 2>&1
    
    sudo systemctl enable docker >/dev/null 2>&1
    sudo systemctl start docker >/dev/null 2>&1
    
    log_success "系统依赖安装完成"
}

install_centos_deps() {
    log "更新软件包列表..."
    sudo yum update -y -q
    
    log "安装系统依赖..."
    sudo yum install -y nginx httpd-tools \
        python3 python3-pip \
        curl wget bc net-tools >/dev/null 2>&1
    
    sudo yum install -y yum-utils >/dev/null 2>&1
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
    sudo yum install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
    
    sudo systemctl enable docker >/dev/null 2>&1
    sudo systemctl start docker >/dev/null 2>&1
    
    log_success "系统依赖安装完成"
}

install_python_deps() {
    log "安装Python依赖..."
    
    # 创建虚拟环境
    if [ ! -d "$VENV_DIR" ]; then
        log "创建Python虚拟环境..."
        python3 -m venv "$VENV_DIR" || {
            log_warning "虚拟环境创建失败，将使用系统Python"
            python3 -m pip install --user --break-system-packages plotly pandas numpy pillow nbformat 2>/dev/null || \
                python3 -m pip install --user plotly pandas numpy pillow nbformat
            log_success "Python依赖安装完成"
            return
        }
    fi
    
    # 激活虚拟环境
    source "$VENV_DIR/bin/activate"
    
    # 安装依赖
    if [ -f "${SCRIPT_DIR}/requirements.txt" ]; then
        pip install -q -r "${SCRIPT_DIR}/requirements.txt"
    else
        pip install -q plotly pandas numpy pillow nbformat
    fi
    
    log_success "Python依赖已安装到虚拟环境"
}

verify_installation() {
    log "验证安装..."
    
    local all_ok=true
    command -v nginx >/dev/null 2>&1 || { log_error "nginx未安装"; all_ok=false; }
    command -v docker >/dev/null 2>&1 || { log_error "docker未安装"; all_ok=false; }
    command -v python3 >/dev/null 2>&1 || { log_error "python3未安装"; all_ok=false; }
    command -v ab >/dev/null 2>&1 || { log_error "ab未安装"; all_ok=false; }
    
    # 验证Python包
    if [ -d "$VENV_DIR" ]; then
        source "$VENV_DIR/bin/activate"
    fi
    
    python3 -c "import plotly" 2>/dev/null || { log_error "plotly未安装"; all_ok=false; }
    python3 -c "import pandas" 2>/dev/null || { log_error "pandas未安装"; all_ok=false; }
    
    if [ "$all_ok" = true ]; then
        log_success "所有依赖验证通过"
        return 0
    else
        log_error "部分依赖未正确安装"
        return 1
    fi
}

main() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  实验依赖安装"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    detect_os
    
    case $OS in
        ubuntu|debian)
            install_ubuntu_deps
            ;;
        centos|rhel|fedora)
            install_centos_deps
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    install_python_deps
    
    if verify_installation; then
        echo ""
        log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_success "  依赖安装完成！"
        log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        log "现在可以运行实验: bash run_experiment.sh"
        echo ""
    else
        log_error "安装完成但验证失败，请检查错误信息"
        exit 1
    fi
}

main "$@"
