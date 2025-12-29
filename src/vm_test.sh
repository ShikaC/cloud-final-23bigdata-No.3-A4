#!/bin/bash
# =============================================================================
# 精简版 KVM (QEMU) 部署与性能采集脚本
# 关注：启动时间、CPU占用、内存占用、磁盘占用，输出CSV
# =============================================================================

set -euo pipefail

VM_NAME="kvm-nginx"
APP_PORT=8080
OUTPUT_DIR="./results/kvm"
PERF_CSV=""
VM_CPU=2
VM_MEMORY_MB=1024
VM_DISK_SIZE="5G"
BASE_IMAGE_NAME="ubuntu-22.04-server-cloudimg-amd64.img"
BASE_IMAGE_PATH="/var/lib/libvirt/images/${BASE_IMAGE_NAME}"
VM_DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
CLOUD_ISO="/var/lib/libvirt/images/${VM_NAME}-seed.iso"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm-name) VM_NAME="$2"; VM_DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"; CLOUD_ISO="/var/lib/libvirt/images/${VM_NAME}-seed.iso"; shift 2;;
        --app-port) APP_PORT="$2"; shift 2;;
        --output-dir) OUTPUT_DIR="$2"; shift 2;;
        --perf-csv) PERF_CSV="$2"; shift 2;;
        --cpu) VM_CPU="$2"; shift 2;;
        --memory-mb) VM_MEMORY_MB="$2"; shift 2;;
        --disk-size) VM_DISK_SIZE="$2"; shift 2;;
        *) echo "未知参数: $1"; exit 1;;
    esac
done

mkdir -p "${OUTPUT_DIR}"

log() { echo -e "[KVM] $*"; }

write_placeholder() {
    log "缺少必要环境，生成占位数据"
    cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,0
cpu_percent,0
memory_mb,0
disk_mb,0
vm_ip,unavailable
EOF
    echo "unavailable" > "${OUTPUT_DIR}/vm_ip.txt"
    if [[ -n "${PERF_CSV}" ]]; then
        echo "kvm,0,0,0,0" >> "${PERF_CSV}"
    fi
    exit 0
}

# 基础依赖检查
missing=()
for bin in virsh virt-install qemu-img curl; do
    command -v "${bin}" >/dev/null 2>&1 || missing+=("${bin}")
done

# KVM 设备检测
if [[ ! -c /dev/kvm ]]; then
    missing+=("/dev/kvm(未启用或无嵌套虚拟化)")
fi

# cloud-init ISO 工具
has_iso_tool=true
if ! command -v cloud-localds >/dev/null 2>&1 && ! command -v genisoimage >/dev/null 2>&1 && ! command -v mkisofs >/dev/null 2>&1; then
    has_iso_tool=false
fi

if [[ ${#missing[@]} -ne 0 ]] || [[ "${has_iso_tool}" = false ]]; then
    log "缺少依赖/能力: ${missing[*]}${has_iso_tool:-}"
    $has_iso_tool || log "缺少 cloud-init ISO 工具 (cloud-localds / genisoimage / mkisofs)"
    log "在 WSL/虚拟机中需开启嵌套虚拟化并安装 libvirt/qemu-kvm。"
    write_placeholder
fi

# 下载基础镜像
if [[ ! -f "${BASE_IMAGE_PATH}" ]]; then
    log "下载 Ubuntu cloud image..."
    mkdir -p "$(dirname "${BASE_IMAGE_PATH}")"
    wget -q -O "${BASE_IMAGE_PATH}" "https://cloud-images.ubuntu.com/releases/22.04/release/${BASE_IMAGE_NAME}" || write_placeholder
fi

# 准备 cloud-init 配置
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/user-data" <<EOF
#cloud-config
package_update: true
package_upgrade: false
packages:
  - nginx
  - curl
  - qemu-guest-agent
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable nginx
  - systemctl start nginx
  - echo "Hello from KVM" > /var/www/html/index.html
EOF

cat > "${TMP_DIR}/meta-data" <<EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds "${CLOUD_ISO}" "${TMP_DIR}/user-data" "${TMP_DIR}/meta-data"
else
    genisoimage -output "${CLOUD_ISO}" -volid cidata -joliet -rock "${TMP_DIR}/user-data" "${TMP_DIR}/meta-data" 2>/dev/null || mkisofs -output "${CLOUD_ISO}" -volid cidata -joliet -rock "${TMP_DIR}/user-data" "${TMP_DIR}/meta-data" 2>/dev/null
fi

# 准备磁盘
cp "${BASE_IMAGE_PATH}" "${VM_DISK_PATH}"
qemu-img resize "${VM_DISK_PATH}" "${VM_DISK_SIZE}"

# 确保默认网络可用
if ! virsh net-list --all | grep -q "default"; then
    log "创建默认网络..."
    cat > "${TMP_DIR}/default-net.xml" <<'EOF'
<network>
  <name>default</name>
  <bridge name="virbr0"/>
  <forward mode="nat"/>
  <ip address="192.168.122.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.122.2" end="192.168.122.254"/>
    </dhcp>
  </ip>
</network>
EOF
    virsh net-define "${TMP_DIR}/default-net.xml" >/dev/null 2>&1 || true
fi
virsh net-start default >/dev/null 2>&1 || true
virsh net-autostart default >/dev/null 2>&1 || true

# 如果存在旧VM则清理
if virsh list --all | grep -q "${VM_NAME}"; then
    virsh destroy "${VM_NAME}" >/dev/null 2>&1 || true
    virsh undefine "${VM_NAME}" >/dev/null 2>&1 || true
fi

log "启动 KVM 虚拟机并记录启动时间..."
START_TIME=$(date +%s.%N)
virt-install \
  --name "${VM_NAME}" \
  --memory "${VM_MEMORY_MB}" \
  --vcpus "${VM_CPU}" \
  --disk "path=${VM_DISK_PATH},format=qcow2" \
  --disk "path=${CLOUD_ISO},device=cdrom" \
  --network network=default \
  --graphics none \
  --noautoconsole \
  --osinfo ubuntu22.04 \
  --import \
  --wait 0 >/dev/null 2>&1 || write_placeholder

virsh start "${VM_NAME}" >/dev/null 2>&1 || true
END_TIME=$(date +%s.%N)
STARTUP_TIME=$(python3 - <<PY
from decimal import Decimal
print(Decimal("${END_TIME}") - Decimal("${START_TIME}"))
PY
)

# 获取 IP
log "等待 VM 获得 IP..."
VM_IP=""
for _ in {1..40}; do
    VM_IP=$(virsh domifaddr "${VM_NAME}" --source agent 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1)
    [[ -z "${VM_IP}" ]] && VM_IP=$(virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/ {print $4}' | cut -d/ -f1 | head -1)
    [[ -n "${VM_IP}" ]] && break
    sleep 2
done
[[ -z "${VM_IP}" ]] && VM_IP="unavailable"
echo "${VM_IP}" > "${OUTPUT_DIR}/vm_ip.txt"

# 检查 Nginx 可用性
if [[ "${VM_IP}" != "unavailable" ]]; then
    for _ in {1..20}; do
        if curl -s "http://${VM_IP}:${APP_PORT}" >/dev/null 2>&1; then
            break
        fi
        sleep 2
    done
fi

# 采集 CPU 使用率（2 秒窗口）
CPU_BEFORE=$(virsh domstats --vcpu "${VM_NAME}" 2>/dev/null | awk '/vcpu.time/ {print $3}' | paste -sd+ - || echo 0)
sleep 2
CPU_AFTER=$(virsh domstats --vcpu "${VM_NAME}" 2>/dev/null | awk '/vcpu.time/ {print $3}' | paste -sd+ - || echo 0)
CPU_PERCENT=$(python3 - <<PY
try:
    start=float("${CPU_BEFORE}")
    end=float("${CPU_AFTER}")
    interval=2.0
    vcpu=int("${VM_CPU}")
    pct=((end-start)/1e9)/interval/vcpu*100
    print(f"{max(pct,0):.2f}")
except Exception:
    print("0")
PY
)

# 内存占用
MEM_RSS_KB=$(virsh dommemstat "${VM_NAME}" 2>/dev/null | awk '/rss/ {print $2}' | head -1)
MEMORY_MB=$(python3 - <<PY
try:
    rss=float("${MEM_RSS_KB or 0}")
    print(f"{rss/1024:.2f}")
except Exception:
    print("${VM_MEMORY_MB}")
PY
)

# 磁盘占用（虚拟磁盘大小）
DISK_BYTES=$(python3 - <<PY
import json, subprocess, os
try:
    info=json.loads(subprocess.check_output(["qemu-img","info","--output","json","${VM_DISK_PATH}"]))
    print(int(info.get("virtual-size",0)))
except Exception:
    try:
        print(os.path.getsize("${VM_DISK_PATH}"))
    except Exception:
        print(0)
PY
)
DISK_MB=$(python3 - <<PY
try:
    print(f"{float(${DISK_BYTES})/1024/1024:.2f}")
except Exception:
    print("0")
PY
)

# 写出指标
cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,${STARTUP_TIME}
cpu_percent,${CPU_PERCENT}
memory_mb,${MEMORY_MB}
disk_mb,${DISK_MB}
vm_ip,${VM_IP}
EOF

if [[ -n "${PERF_CSV}" ]]; then
    echo "kvm,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"
fi

log "完成，数据已写入 ${OUTPUT_DIR}"

