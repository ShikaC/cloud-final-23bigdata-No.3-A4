#!/bin/bash
# =============================================================================
# 清理脚本 - 清理实验创建的VM和Docker容器
# =============================================================================
# 功能说明：
#   清理实验过程中创建的VM、Docker容器和相关资源
#
# 使用方法：
#   sudo bash cleanup.sh [--all]
#   --all: 同时清理结果目录
# =============================================================================

set -e

# 默认参数
CLEAN_ALL=false
VM_NAME="test-vm-nginx"
DOCKER_CONTAINER_NAME="test-docker-nginx"

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            CLEAN_ALL=true
            shift
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --container-name)
            DOCKER_CONTAINER_NAME="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[清理]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 清理VM
cleanup_vm() {
    log_info "清理VM: ${VM_NAME}"
    
    # 检查VM是否存在
    if virsh list --all 2>/dev/null | grep -q "${VM_NAME}"; then
        # 停止VM
        if virsh list | grep -q "${VM_NAME}"; then
            log_info "停止VM..."
            virsh destroy "${VM_NAME}" 2>/dev/null || true
        fi
        
        # 删除VM定义
        log_info "删除VM定义..."
        virsh undefine "${VM_NAME}" 2>/dev/null || true
        
        log_success "VM已清理"
    else
        log_info "VM不存在，跳过"
    fi
    
    # 清理VM磁盘镜像
    VM_DISK="/var/lib/libvirt/images/${VM_NAME}.qcow2"
    if [ -f "${VM_DISK}" ]; then
        log_info "删除VM磁盘镜像..."
        sudo rm -f "${VM_DISK}"
        log_success "VM磁盘镜像已删除"
    fi
    
    # 清理cloud-init ISO
    CLOUD_INIT_ISO="/var/lib/libvirt/images/${VM_NAME}-cloudinit.iso"
    if [ -f "${CLOUD_INIT_ISO}" ]; then
        log_info "删除cloud-init ISO..."
        sudo rm -f "${CLOUD_INIT_ISO}"
    fi
    
    # 清理临时目录
    CLOUD_INIT_DIR="/tmp/${VM_NAME}-cloudinit"
    if [ -d "${CLOUD_INIT_DIR}" ]; then
        log_info "清理临时目录..."
        rm -rf "${CLOUD_INIT_DIR}"
    fi
}

# 清理Docker容器
cleanup_docker() {
    log_info "清理Docker容器: ${DOCKER_CONTAINER_NAME}"
    
    # 检查容器是否存在
    if docker ps -a 2>/dev/null | grep -q "${DOCKER_CONTAINER_NAME}"; then
        # 停止容器
        if docker ps | grep -q "${DOCKER_CONTAINER_NAME}"; then
            log_info "停止容器..."
            docker stop "${DOCKER_CONTAINER_NAME}" 2>/dev/null || true
        fi
        
        # 删除容器
        log_info "删除容器..."
        docker rm "${DOCKER_CONTAINER_NAME}" 2>/dev/null || true
        
        log_success "Docker容器已清理"
    else
        log_info "Docker容器不存在，跳过"
    fi
}

# 清理结果目录
cleanup_results() {
    if [ "$CLEAN_ALL" = true ]; then
        log_info "清理结果目录..."
        if [ -d "results" ]; then
            read -p "确定要删除所有实验结果吗? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf results
                log_success "结果目录已删除"
            else
                log_info "保留结果目录"
            fi
        fi
    else
        log_info "使用 --all 参数可同时清理结果目录"
    fi
}

# 主函数
main() {
    log_info "=========================================="
    log_info "实验资源清理脚本"
    log_info "=========================================="
    
    # 检查权限
    if [ "$EUID" -ne 0 ]; then 
        log_warning "建议使用sudo运行以清理所有资源"
    fi
    
    # 清理VM
    cleanup_vm
    
    # 清理Docker
    cleanup_docker
    
    # 清理结果目录（可选）
    cleanup_results
    
    log_success "=========================================="
    log_success "清理完成！"
    log_success "=========================================="
}

main "$@"

