#!/bin/bash
# =============================================================================
# Python 环境诊断脚本
# =============================================================================
# 功能说明：
#   诊断 Python 环境，检查是否满足创建虚拟环境的要求
#
# 使用方法：
#   bash 诊断Python环境.sh
# =============================================================================

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[诊断]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

echo "=========================================="
echo "Python 环境诊断"
echo "=========================================="
echo ""

# 1. 检查 Python3 是否安装
log_info "1. 检查 Python3..."
if command -v python3 >/dev/null 2>&1; then
    PYTHON_PATH=$(which python3)
    PYTHON_VERSION=$(python3 --version 2>&1)
    log_success "Python3 已安装"
    log_info "  路径: $PYTHON_PATH"
    log_info "  版本: $PYTHON_VERSION"
else
    log_error "Python3 未安装"
    echo ""
    echo "安装方法:"
    echo "  Ubuntu/Debian: sudo apt-get install -y python3"
    echo "  CentOS/RHEL: sudo yum install -y python3"
    exit 1
fi

# 2. 检查 Python 版本
log_info "2. 检查 Python 版本..."
PYTHON_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo "0")
PYTHON_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "0")
PYTHON_VERSION_STR="${PYTHON_MAJOR}.${PYTHON_MINOR}"

if [ "$PYTHON_MAJOR" -lt 3 ]; then
    log_error "Python 版本过低: $PYTHON_VERSION_STR (需要 3.6+)"
    exit 1
elif [ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 6 ]; then
    log_error "Python 版本过低: $PYTHON_VERSION_STR (需要 3.6+)"
    exit 1
else
    log_success "Python 版本: $PYTHON_VERSION_STR (满足要求)"
fi

# 3. 检查 venv 模块
log_info "3. 检查 venv 模块..."
if python3 -m venv --help >/dev/null 2>&1; then
    log_success "venv 模块可用"
else
    log_error "venv 模块不可用"
    echo ""
    echo "安装方法:"
    echo "  Ubuntu/Debian: sudo apt-get install -y python3-venv"
    echo "  CentOS/RHEL: sudo yum install -y python3-venv"
    exit 1
fi

# 4. 检查 pip
log_info "4. 检查 pip..."
if command -v pip3 >/dev/null 2>&1; then
    PIP_VERSION=$(pip3 --version 2>&1)
    log_success "pip3 已安装: $PIP_VERSION"
else
    log_warning "pip3 未安装"
    echo ""
    echo "安装方法:"
    echo "  Ubuntu/Debian: sudo apt-get install -y python3-pip"
    echo "  或使用: python3 -m ensurepip --upgrade"
fi

# 5. 检查磁盘空间
log_info "5. 检查磁盘空间..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AVAILABLE_SPACE=$(df -BG "$SCRIPT_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/G//' || echo "unknown")
if [ "$AVAILABLE_SPACE" != "unknown" ] && [ -n "$AVAILABLE_SPACE" ]; then
    if [ "$AVAILABLE_SPACE" -ge 2 ]; then
        log_success "可用磁盘空间: ${AVAILABLE_SPACE}GB (充足)"
    else
        log_warning "可用磁盘空间: ${AVAILABLE_SPACE}GB (建议至少 2GB)"
    fi
else
    log_warning "无法检查磁盘空间"
fi

# 6. 检查权限
log_info "6. 检查目录权限..."
if [ -w "$SCRIPT_DIR" ]; then
    log_success "有写入权限: $SCRIPT_DIR"
else
    log_error "没有写入权限: $SCRIPT_DIR"
    echo ""
    echo "修复方法:"
    echo "  sudo chown -R \$USER:\$USER $SCRIPT_DIR"
    exit 1
fi

# 7. 测试创建虚拟环境（临时）
log_info "7. 测试创建虚拟环境..."
TEST_VENV_DIR="${SCRIPT_DIR}/.test_venv_$$"
if python3 -m venv "$TEST_VENV_DIR" 2>/dev/null; then
    log_success "可以创建虚拟环境"
    rm -rf "$TEST_VENV_DIR"
else
    log_error "无法创建虚拟环境"
    echo ""
    echo "可能的原因:"
    echo "  1. python3-venv 未安装"
    echo "  2. 权限不足"
    echo "  3. 磁盘空间不足"
    rm -rf "$TEST_VENV_DIR" 2>/dev/null
    exit 1
fi

echo ""
echo "=========================================="
log_success "所有检查通过！可以创建虚拟环境"
echo "=========================================="
echo ""
echo "创建虚拟环境:"
echo "  python3 -m venv venv"
echo "  source venv/bin/activate"
echo "  pip3 install -r requirements.txt"

