#!/bin/bash
# =============================================================================
# 修复虚拟环境脚本
# =============================================================================
# 功能说明：
#   修复损坏或不完整的虚拟环境
#
# 使用方法：
#   bash 修复虚拟环境.sh
# =============================================================================

set -e

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[修复]${NC} $1"
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

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/venv"

log_info "=========================================="
log_info "虚拟环境修复脚本"
log_info "=========================================="
log_info "脚本目录: $SCRIPT_DIR"
log_info "虚拟环境目录: $VENV_DIR"
log_info ""

# 检查是否在 WSL 中访问 Windows 文件系统
if [[ "$SCRIPT_DIR" == /mnt/* ]]; then
    log_warning "检测到在 WSL 中访问 Windows 文件系统"
    log_warning "这可能导致虚拟环境性能问题或兼容性问题"
    log_info ""
    log_info "建议操作:"
    log_info "  1. 将项目复制到 WSL 文件系统:"
    log_info "     cp -r $SCRIPT_DIR ~/cloud-computing-project"
    log_info "     cd ~/cloud-computing-project"
    log_info "  2. 然后重新运行此脚本"
    log_info ""
    read -p "是否继续在当前位置修复? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "已取消"
        exit 0
    fi
fi

# 步骤1: 删除损坏的虚拟环境
if [ -d "$VENV_DIR" ]; then
    log_info "步骤1: 删除旧的虚拟环境..."
    rm -rf "$VENV_DIR"
    log_success "已删除旧的虚拟环境"
else
    log_info "步骤1: 未找到现有虚拟环境，将创建新的"
fi

# 步骤2: 诊断环境
log_info "步骤2: 诊断环境..."

# 检查 Python3
if ! command -v python3 >/dev/null 2>&1; then
    log_error "Python3 未安装"
    log_info "请安装 Python3: sudo apt-get install -y python3 python3-venv"
    exit 1
fi

PYTHON_VERSION=$(python3 --version 2>&1)
log_info "Python 版本: $PYTHON_VERSION"

# 检查 Python 版本（需要 3.6+）
PYTHON_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo "0")
PYTHON_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "0")

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 6 ]); then
    log_error "Python 版本过低 (需要 3.6+)，当前版本: $PYTHON_VERSION"
    log_info "请升级 Python: sudo apt-get install -y python3.8 python3.8-venv"
    exit 1
fi

# 检查 venv 模块
if ! python3 -m venv --help >/dev/null 2>&1; then
    log_error "Python venv 模块不可用"
    log_info "请安装 python3-venv: sudo apt-get install -y python3-venv"
    exit 1
fi

# 检查磁盘空间
AVAILABLE_SPACE=$(df -BG "$SCRIPT_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
if [ -n "$AVAILABLE_SPACE" ] && [ "$AVAILABLE_SPACE" -lt 1 ]; then
    log_warning "可用磁盘空间可能不足: ${AVAILABLE_SPACE}GB"
    log_info "建议至少 2GB 可用空间"
fi

# 检查权限
if [ ! -w "$SCRIPT_DIR" ]; then
    log_error "没有写入权限: $SCRIPT_DIR"
    log_info "请检查权限: ls -ld $SCRIPT_DIR"
    log_info "或使用: sudo chown -R \$USER:\$USER $SCRIPT_DIR"
    exit 1
fi

log_success "环境诊断通过"

# 步骤3: 创建新的虚拟环境
log_info "步骤3: 创建新的虚拟环境..."
cd "$SCRIPT_DIR"

# 尝试创建虚拟环境，捕获详细错误
if python3 -m venv "$VENV_DIR" 2>&1 | tee /tmp/venv_error.log; then
    log_success "虚拟环境创建成功"
else
    VENV_ERROR=$(cat /tmp/venv_error.log 2>/dev/null || echo "未知错误")
    log_error "创建虚拟环境失败"
    log_error "错误详情: $VENV_ERROR"
    log_info ""
    log_info "可能的原因和解决方案:"
    log_info ""
    log_info "1. Python3-venv 未安装:"
    log_info "   sudo apt-get install -y python3-venv"
    log_info ""
    log_info "2. 权限问题:"
    log_info "   sudo chown -R \$USER:\$USER $SCRIPT_DIR"
    log_info "   或使用: python3 -m venv --without-pip $VENV_DIR"
    log_info ""
    log_info "3. 磁盘空间不足:"
    log_info "   df -h $SCRIPT_DIR"
    log_info "   清理磁盘空间后重试"
    log_info ""
    log_info "4. 尝试使用 virtualenv (如果可用):"
    log_info "   pip3 install virtualenv"
    log_info "   virtualenv $VENV_DIR"
    log_info ""
    
    # 尝试使用 --without-pip 创建
    log_info "尝试使用 --without-pip 选项创建虚拟环境..."
    if python3 -m venv --without-pip "$VENV_DIR" 2>/dev/null; then
        log_success "使用 --without-pip 创建成功"
        log_info "需要手动安装 pip"
        source "$VENV_DIR/bin/activate"
        curl https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
        python3 /tmp/get-pip.py
        rm /tmp/get-pip.py
    else
        log_error "所有创建方法都失败"
        exit 1
    fi
fi

# 验证虚拟环境是否完整
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    log_error "虚拟环境创建不完整，激活脚本不存在"
    exit 1
fi

log_success "虚拟环境创建成功"

# 步骤4: 验证虚拟环境
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    log_error "虚拟环境创建不完整，激活脚本不存在"
    exit 1
fi

if [ ! -f "$VENV_DIR/bin/python3" ]; then
    log_error "虚拟环境创建不完整，Python 可执行文件不存在"
    exit 1
fi

log_success "虚拟环境验证通过"

# 步骤5: 激活虚拟环境
log_info "步骤5: 激活虚拟环境..."
source "$VENV_DIR/bin/activate" || {
    log_error "无法激活虚拟环境"
    log_info "请检查: ls -la $VENV_DIR/bin/activate"
    exit 1
}
log_success "已激活虚拟环境: $VIRTUAL_ENV"

# 验证激活后的 Python
ACTIVATED_PYTHON=$(which python3)
log_info "激活后的 Python: $ACTIVATED_PYTHON"

# 步骤6: 升级 pip
log_info "步骤4: 升级 pip..."
pip3 install --upgrade pip setuptools wheel || {
    log_error "升级 pip 失败"
    exit 1
}
log_success "pip 已升级"

# 步骤7: 安装依赖
log_info "步骤7: 安装Python依赖..."
if [ -f "$SCRIPT_DIR/requirements.txt" ]; then
    pip3 install -r "$SCRIPT_DIR/requirements.txt" || {
        log_error "安装依赖失败"
        log_info "尝试逐个安装..."
        pip3 install matplotlib pandas seaborn numpy || {
            log_error "安装依赖失败，请检查网络连接或手动安装"
            exit 1
        }
    }
else
    log_info "未找到 requirements.txt，安装默认依赖..."
    pip3 install matplotlib pandas seaborn numpy || {
        log_error "安装依赖失败"
        exit 1
    }
fi
log_success "依赖安装完成"

# 步骤8: 验证安装
log_info "步骤8: 验证安装..."
python3 -c "import matplotlib" 2>/dev/null || { log_error "matplotlib 未安装"; exit 1; }
python3 -c "import pandas" 2>/dev/null || { log_error "pandas 未安装"; exit 1; }
python3 -c "import seaborn" 2>/dev/null || { log_error "seaborn 未安装"; exit 1; }
python3 -c "import numpy" 2>/dev/null || { log_error "numpy 未安装"; exit 1; }

log_success "=========================================="
log_success "虚拟环境修复完成！"
log_success "=========================================="
log_info ""
log_info "虚拟环境位置: $VENV_DIR"
log_info "激活命令: source $VENV_DIR/bin/activate"
log_info ""
log_info "现在可以运行实验: sudo ./run_experiment.sh"
log_info "（脚本会自动激活虚拟环境）"

