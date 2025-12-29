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

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[安装]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VER=$(lsb_release -sr)
    else
        log_error "无法检测操作系统类型"
        exit 1
    fi
    
    log_info "检测到操作系统: $OS $VER"
}

# 安装Ubuntu/Debian依赖
install_ubuntu_deps() {
    log_info "更新软件包列表..."
    sudo apt-get update
    
    # 确保启用universe软件源（Ubuntu）
    if [ -f /etc/apt/sources.list ]; then
        if ! grep -q "universe" /etc/apt/sources.list 2>/dev/null; then
            log_info "启用universe软件源..."
            sudo add-apt-repository -y universe 2>/dev/null || true
            sudo apt-get update
        fi
    fi
    
    log_info "安装KVM和相关工具..."
    sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
    # virt-install 可能在不同的包中，尝试多种方式
    if ! sudo apt-get install -y virt-install 2>/dev/null; then
        log_info "尝试安装 virtinst 包（包含 virt-install）..."
        sudo apt-get install -y virtinst || {
            log_warning "virt-install 安装失败，尝试安装完整虚拟化工具包..."
            sudo apt-get install -y virt-manager virt-viewer || {
                log_error "无法安装 virt-install，请手动安装"
                log_info "可以尝试: sudo apt-get install -y virtinst 或 sudo apt-get install -y virt-manager"
            }
        }
    fi
    sudo apt-get install -y qemu-utils
    # genisoimage 或 mkisofs
    if ! sudo apt-get install -y genisoimage 2>/dev/null; then
        log_info "安装 mkisofs（genisoimage 的替代）..."
        sudo apt-get install -y mkisofs || log_warning "无法安装 ISO 创建工具"
    fi
    
    log_info "安装Docker..."
    sudo apt-get install -y docker.io docker-compose
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log_info "安装Apache Bench..."
    sudo apt-get install -y apache2-utils
    
    log_info "安装Python和依赖..."
    sudo apt-get install -y python3 python3-pip python3-dev
    sudo apt-get install -y build-essential
    
    log_info "安装其他工具..."
    sudo apt-get install -y curl wget bc ssh-client
    
    log_success "Ubuntu/Debian依赖安装完成"
}

# 安装CentOS/RHEL依赖
install_centos_deps() {
    log_info "更新软件包列表..."
    sudo yum update -y
    
    log_info "安装KVM和相关工具..."
    sudo yum install -y qemu-kvm libvirt libvirt-python libguestfs-tools virt-install virt-manager
    sudo yum install -y genisoimage
    
    log_info "安装Docker..."
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io
    sudo systemctl enable docker
    sudo systemctl start docker
    
    log_info "安装Apache Bench..."
    sudo yum install -y httpd-tools
    
    log_info "安装Python和依赖..."
    sudo yum install -y python3 python3-pip python3-devel
    sudo yum install -y gcc gcc-c++ make
    
    log_info "安装其他工具..."
    sudo yum install -y curl wget bc openssh-clients
    
    log_success "CentOS/RHEL依赖安装完成"
}

# 安装Python依赖
install_python_deps() {
    log_info "安装Python依赖包..."
    
    # 获取脚本所在目录（确保虚拟环境创建在正确位置）
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VENV_DIR="${SCRIPT_DIR}/venv"
    
    # 检查是否是受保护的系统Python（PEP 668）
    local use_venv=false
    if python3 -m pip install --dry-run matplotlib 2>&1 | grep -q "externally-managed-environment"; then
        log_warning "检测到受保护的系统Python环境（PEP 668）"
        log_info "推荐使用虚拟环境，避免影响系统Python"
        
        # 默认使用虚拟环境（非交互模式）
        use_venv=true
    fi
    
    # 检查现有虚拟环境是否完整
    if [ -d "$VENV_DIR" ]; then
        if [ ! -f "$VENV_DIR/bin/activate" ]; then
            log_warning "检测到损坏的虚拟环境，将重新创建..."
            rm -rf "$VENV_DIR"
        else
            log_info "虚拟环境已存在: $VENV_DIR"
        fi
    fi
    
    # 创建并使用虚拟环境（推荐方式）
    if [ "$use_venv" = true ] || [ ! -d "$VENV_DIR" ]; then
        log_info "创建Python虚拟环境: $VENV_DIR"
        cd "$SCRIPT_DIR"  # 确保在正确目录中创建
        
        # 检查是否在 WSL 中访问 Windows 文件系统（性能问题）
        if [[ "$VENV_DIR" == /mnt/* ]]; then
            log_warning "检测到在 WSL 中访问 Windows 文件系统，虚拟环境性能可能较差"
            log_info "建议将项目复制到 WSL 文件系统: cp -r /mnt/c/Users/... ~/project"
        fi
        
        python3 -m venv "$VENV_DIR" || {
            log_error "无法创建虚拟环境"
            log_info "可能的原因:"
            log_info "  1. 权限不足 - 尝试: sudo chown -R \$USER:\$USER $SCRIPT_DIR"
            log_info "  2. 磁盘空间不足"
            log_info "  3. 在 WSL 中访问 Windows 文件系统可能有兼容性问题"
            log_info "建议: 将项目复制到 WSL 的 home 目录"
            use_venv=false
        }
        
        # 验证虚拟环境是否创建成功
        if [ -d "$VENV_DIR" ] && [ ! -f "$VENV_DIR/bin/activate" ]; then
            log_error "虚拟环境创建不完整，删除并重试..."
            rm -rf "$VENV_DIR"
            use_venv=false
        fi
    fi
    
    if [ "$use_venv" = true ] && [ -d "$VENV_DIR" ]; then
        log_info "激活虚拟环境: $VENV_DIR"
        if [ -f "$VENV_DIR/bin/activate" ]; then
            source "$VENV_DIR/bin/activate"
            log_success "已激活虚拟环境: $VIRTUAL_ENV"
            pip_flags=""
        else
            log_error "虚拟环境目录存在但激活脚本不存在: $VENV_DIR/bin/activate"
            log_info "尝试重新创建虚拟环境..."
            rm -rf "$VENV_DIR"
            python3 -m venv "$VENV_DIR" || {
                log_error "重新创建虚拟环境失败"
                use_venv=false
            }
            if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
                source "$VENV_DIR/bin/activate"
                log_success "已重新创建并激活虚拟环境"
                pip_flags=""
            else
                use_venv=false
            fi
        fi
    fi
    
    if [ "$use_venv" != true ] || [ -z "$VIRTUAL_ENV" ]; then
        # 检查 pip 版本是否支持 --break-system-packages
        pip_version=$(pip3 --version 2>/dev/null | grep -oP 'pip \K[0-9]+\.[0-9]+' | head -1 || echo "0.0")
        pip_major=$(echo $pip_version | cut -d. -f1)
        pip_minor=$(echo $pip_version | cut -d. -f2)
        
        if [ "$pip_major" -lt 23 ] || ([ "$pip_major" -eq 23 ] && [ "$pip_minor" -lt 0 ]); then
            log_warning "pip 版本 ($pip_version) 可能不支持 --break-system-packages"
            log_info "尝试创建虚拟环境..."
            cd "$SCRIPT_DIR"
            if python3 -m venv "$VENV_DIR" 2>/dev/null && [ -f "$VENV_DIR/bin/activate" ]; then
                source "$VENV_DIR/bin/activate"
                log_success "已创建并激活虚拟环境"
                pip_flags=""
            else
                log_error "无法创建虚拟环境，且 pip 版本可能不支持 --break-system-packages"
                log_info "请手动升级 pip: python3 -m pip install --upgrade pip"
                log_info "或手动创建虚拟环境: cd $SCRIPT_DIR && python3 -m venv venv && source venv/bin/activate"
                pip_flags="--break-system-packages"
            fi
        else
            # 使用 --break-system-packages
            pip_flags="--break-system-packages"
            log_warning "使用 --break-system-packages 标志安装到系统Python"
            log_warning "这可能会影响系统Python，建议使用虚拟环境"
        fi
    fi
    
    # 升级pip（只在虚拟环境中或使用 --break-system-packages）
    log_info "升级pip..."
    if [ -n "$VIRTUAL_ENV" ]; then
        # 在虚拟环境中，不需要特殊标志
        pip3 install --upgrade pip setuptools wheel 2>/dev/null || true
    elif [ -n "$pip_flags" ]; then
        # 使用 --break-system-packages
        pip3 install $pip_flags --upgrade pip setuptools wheel 2>/dev/null || {
            log_warning "升级 pip 失败，尝试不使用 --break-system-packages"
            pip3 install --upgrade pip setuptools wheel --user 2>/dev/null || true
        }
    else
        pip3 install --upgrade pip setuptools wheel --user 2>/dev/null || true
    fi
    
    # 安装依赖
    log_info "安装Python依赖包..."
    if [ -f "requirements.txt" ]; then
        if [ -n "$VIRTUAL_ENV" ]; then
            # 虚拟环境中，不需要特殊标志
            pip3 install -r requirements.txt || {
                log_error "安装依赖失败"
                return 1
            }
        elif [ -n "$pip_flags" ]; then
            # 使用 --break-system-packages
            pip3 install $pip_flags -r requirements.txt || {
                log_error "安装依赖失败，尝试使用 --user 标志"
                pip3 install --user -r requirements.txt || {
                    log_error "安装失败，请手动安装或使用虚拟环境"
                    return 1
                }
            }
        else
            pip3 install --user -r requirements.txt || {
                log_error "安装依赖失败"
                return 1
            }
        fi
    else
        if [ -n "$VIRTUAL_ENV" ]; then
            pip3 install matplotlib pandas seaborn numpy || {
                log_error "安装依赖失败"
                return 1
            }
        elif [ -n "$pip_flags" ]; then
            pip3 install $pip_flags matplotlib pandas seaborn numpy || {
                log_error "安装依赖失败，尝试使用 --user 标志"
                pip3 install --user matplotlib pandas seaborn numpy || {
                    log_error "安装失败，请手动安装或使用虚拟环境"
                    return 1
                }
            }
        else
            pip3 install --user matplotlib pandas seaborn numpy || {
                log_error "安装依赖失败"
                return 1
            }
        fi
    fi
    
    if [ -n "$VIRTUAL_ENV" ]; then
        log_success "Python依赖已安装到虚拟环境: $VIRTUAL_ENV"
        log_info "运行实验时脚本会自动激活虚拟环境"
    else
        log_success "Python依赖已安装到系统Python"
    fi
    
    log_success "Python依赖安装完成"
}

# 配置KVM
configure_kvm() {
    log_info "配置KVM..."
    
    # 检查CPU虚拟化支持
    if egrep -c '(vmx|svm)' /proc/cpuinfo > 0; then
        log_success "CPU支持虚拟化"
    else
        log_warning "CPU可能不支持虚拟化，VM测试可能无法运行"
    fi
    
    # 启动libvirt服务
    sudo systemctl enable libvirtd
    sudo systemctl start libvirtd
    
    # 检查默认网络
    if sudo virsh net-list --all | grep -q "default.*active"; then
        log_success "Libvirt默认网络已启动"
    else
        log_info "启动Libvirt默认网络..."
        sudo virsh net-start default 2>/dev/null || true
        sudo virsh net-autostart default 2>/dev/null || true
    fi
    
    log_success "KVM配置完成"
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    
    local all_ok=true
    
    # 获取脚本所在目录
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VENV_DIR="${SCRIPT_DIR}/venv"
    
    # 检查命令
    command -v virsh >/dev/null 2>&1 || { log_error "virsh未安装"; all_ok=false; }
    command -v virt-install >/dev/null 2>&1 || { 
        log_warning "virt-install未找到，检查替代方案..."; 
        if command -v virt-manager >/dev/null 2>&1; then
            log_info "找到 virt-manager，可能包含 virt-install"
        else
            log_error "virt-install未安装，VM测试可能无法运行"
            log_info "可以尝试手动安装: sudo apt-get install -y virtinst"
            all_ok=false
        fi
    }
    command -v docker >/dev/null 2>&1 || { log_error "docker未安装"; all_ok=false; }
    command -v python3 >/dev/null 2>&1 || { log_error "python3未安装"; all_ok=false; }
    command -v ab >/dev/null 2>&1 || { log_error "ab工具未安装"; all_ok=false; }
    
    # 检查Python库（如果在虚拟环境中，需要激活）
    if [ -d "$VENV_DIR" ] && [ -f "$VENV_DIR/bin/activate" ]; then
        if [ -z "$VIRTUAL_ENV" ]; then
            log_info "检测到虚拟环境，激活后验证..."
            source "$VENV_DIR/bin/activate" || {
                log_warning "无法激活虚拟环境: $VENV_DIR"
                log_info "尝试使用系统Python验证..."
            }
        else
            log_info "虚拟环境已激活: $VIRTUAL_ENV"
        fi
    else
        if [ -d "$VENV_DIR" ]; then
            log_warning "虚拟环境目录存在但激活脚本不存在: $VENV_DIR/bin/activate"
            log_info "使用系统Python验证..."
        else
            log_info "未检测到虚拟环境，使用系统Python验证..."
        fi
    fi
    
    # 验证Python包
    python3 -c "import matplotlib" 2>/dev/null || { 
        log_error "matplotlib未安装"
        if [ -n "$VIRTUAL_ENV" ]; then
            log_info "提示: 虚拟环境已激活，但matplotlib未安装"
            log_info "请运行: source $VENV_DIR/bin/activate && pip3 install -r $SCRIPT_DIR/requirements.txt"
        else
            log_info "提示: 请安装matplotlib: pip3 install matplotlib 或使用虚拟环境"
        fi
        all_ok=false
    }
    python3 -c "import pandas" 2>/dev/null || { log_error "pandas未安装"; all_ok=false; }
    python3 -c "import seaborn" 2>/dev/null || { 
        log_error "seaborn未安装"
        if [ -n "$VIRTUAL_ENV" ]; then
            log_info "提示: 虚拟环境已激活，但seaborn未安装"
            log_info "请运行: source $VENV_DIR/bin/activate && pip3 install -r $SCRIPT_DIR/requirements.txt"
        fi
        all_ok=false
    }
    
    if [ "$all_ok" = true ]; then
        log_success "所有依赖验证通过！"
        if [ -n "$VIRTUAL_ENV" ]; then
            log_info "Python环境: 虚拟环境 ($VIRTUAL_ENV)"
        else
            log_info "Python环境: 系统Python"
        fi
        return 0
    else
        log_error "部分依赖未正确安装，请检查上述错误"
        log_info ""
        log_info "手动修复建议:"
        if [ -d "$VENV_DIR" ]; then
            log_info "1. 激活虚拟环境: source $VENV_DIR/bin/activate"
            log_info "2. 安装依赖: pip3 install -r $SCRIPT_DIR/requirements.txt"
        else
            log_info "1. 创建虚拟环境: cd $SCRIPT_DIR && python3 -m venv venv"
            log_info "2. 激活虚拟环境: source venv/bin/activate"
            log_info "3. 安装依赖: pip3 install -r requirements.txt"
        fi
        return 1
    fi
}

# 主函数
main() {
    log_info "=========================================="
    log_info "实验依赖安装脚本"
    log_info "=========================================="
    
    # 检查是否为root
    if [ "$EUID" -ne 0 ]; then 
        log_info "需要sudo权限，将提示输入密码"
    fi
    
    # 检测操作系统
    detect_os
    
    # 根据系统类型安装依赖
    case $OS in
        ubuntu|debian)
            install_ubuntu_deps
            ;;
        centos|rhel|fedora)
            install_centos_deps
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            log_info "请手动安装依赖，参考 实验说明.md"
            exit 1
            ;;
    esac
    
    # 安装Python依赖
    install_python_deps
    
    # 配置KVM
    configure_kvm
    
    # 验证安装
    if verify_installation; then
        log_success "=========================================="
        log_success "依赖安装完成！"
        log_success "=========================================="
        log_info "现在可以运行实验: sudo ./run_experiment.sh"
    else
        log_error "安装完成，但部分依赖验证失败"
        log_info "请检查错误信息并手动修复"
        exit 1
    fi
}

main "$@"

