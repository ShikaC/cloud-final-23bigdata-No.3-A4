#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# 实验结果分析脚本
# =============================================================================
# 功能说明：
#   分析VM和Docker的性能测试结果，生成详细的分析报告
#   包括：性能对比、隔离边界分析、适用场景建议等
#
# 使用方法：
#   python3 analyze_results.py --vm-dir ./results/vm --docker-dir ./results/docker --stress-dir ./results --output-file ./results/analysis_report.md
# =============================================================================

import os
import sys
import argparse
import csv
from pathlib import Path
from datetime import datetime


def read_file_content(filepath, default="0"):
    """读取文件内容"""
    try:
        if os.path.exists(filepath):
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                return content if content else default
        return default
    except Exception as e:
        return default


def parse_number(value, default=0):
    """将字符串转换为数字"""
    try:
        value = str(value).strip().replace('MB', '').replace('GB', '').replace('KB', '').replace('B', '')
        return float(value)
    except:
        return default


def format_bytes(bytes_value):
    """格式化字节数为人类可读格式"""
    try:
        bytes_value = float(bytes_value)
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_value < 1024.0:
                return f"{bytes_value:.2f} {unit}"
            bytes_value /= 1024.0
        return f"{bytes_value:.2f} PB"
    except:
        return str(bytes_value)


def load_performance_data(vm_dir, docker_dir):
    """加载性能数据"""
    data = {
        'vm': {},
        'docker': {}
    }
    
    vm_dir_path = Path(vm_dir)
    if vm_dir_path.exists():
        # 内存数据：优先使用used_memory_mb.txt，如果为0则尝试vm_internal_memory_mb.txt，最后使用configured_memory_mb.txt
        used_mem = parse_number(read_file_content(vm_dir_path / 'used_memory_mb.txt'))
        if used_mem == 0:
            used_mem = parse_number(read_file_content(vm_dir_path / 'vm_internal_memory_mb.txt'))
        if used_mem == 0:
            used_mem = parse_number(read_file_content(vm_dir_path / 'configured_memory_mb.txt'))
        
        # 磁盘数据：优先使用disk_actual_bytes.txt，如果为0则尝试其他方法
        disk_bytes = parse_number(read_file_content(vm_dir_path / 'disk_actual_bytes.txt'))
        if disk_bytes == 0:
            # 尝试从disk_size.txt解析（格式可能是 "10G" 或 "10737418240"）
            disk_size_str = read_file_content(vm_dir_path / 'disk_size.txt', '0')
            if 'G' in disk_size_str.upper():
                disk_bytes = parse_number(disk_size_str) * 1024 * 1024 * 1024
            elif 'M' in disk_size_str.upper():
                disk_bytes = parse_number(disk_size_str) * 1024 * 1024
            else:
                disk_bytes = parse_number(disk_size_str)
        
        data['vm'] = {
            'startup_time': parse_number(read_file_content(vm_dir_path / 'startup_time.txt')),
            'memory_mb': used_mem,
            'disk_bytes': disk_bytes,
            'cpu_cores': parse_number(read_file_content(vm_dir_path / 'configured_cpu.txt')),
            'ip': read_file_content(vm_dir_path / 'vm_ip.txt', 'unknown'),
        }
    
    docker_dir_path = Path(docker_dir)
    if docker_dir_path.exists():
        data['docker'] = {
            'startup_time': parse_number(read_file_content(docker_dir_path / 'startup_time.txt')),
            'memory_mb': parse_number(read_file_content(docker_dir_path / 'memory_used_mb.txt')),
            'disk_bytes': parse_number(read_file_content(docker_dir_path / 'total_disk_bytes.txt')),
            'cpu_percent': parse_number(read_file_content(docker_dir_path / 'cpu_percent.txt')),
        }
    
    return data


def load_stress_data(stress_dir):
    """加载压测数据"""
    stress_dir_path = Path(stress_dir)
    data = {
        'vm': {},
        'docker': {}
    }
    
    vm_csv = stress_dir_path / 'stress_vm_results.csv'
    if vm_csv.exists():
        with open(vm_csv, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                key = row['指标']
                value = parse_number(row['值'])
                if 'QPS' in key:
                    data['vm']['qps'] = value
                elif '平均响应时间' in key and '并发' not in key:
                    data['vm']['avg_response_time'] = value
                elif '失败请求数' in key:
                    data['vm']['failed_requests'] = value
                elif '传输速率' in key:
                    data['vm']['transfer_rate'] = value
    
    docker_csv = stress_dir_path / 'stress_docker_results.csv'
    if docker_csv.exists():
        with open(docker_csv, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                key = row['指标']
                value = parse_number(row['值'])
                if 'QPS' in key:
                    data['docker']['qps'] = value
                elif '平均响应时间' in key and '并发' not in key:
                    data['docker']['avg_response_time'] = value
                elif '失败请求数' in key:
                    data['docker']['failed_requests'] = value
                elif '传输速率' in key:
                    data['docker']['transfer_rate'] = value
    
    return data


def calculate_improvement(vm_value, docker_value, higher_is_better=True):
    """计算改进百分比"""
    if vm_value == 0 or docker_value == 0:
        return 0
    
    if higher_is_better:
        # 值越大越好（如QPS）
        improvement = ((docker_value - vm_value) / vm_value) * 100
    else:
        # 值越小越好（如启动时间、内存）
        improvement = ((vm_value - docker_value) / vm_value) * 100
    
    return improvement


def generate_report(perf_data, stress_data, output_file):
    """生成分析报告"""
    
    report = []
    report.append("# 虚拟化 vs 容器性能对比分析报告\n")
    report.append(f"**生成时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    report.append("---\n\n")
    
    # 1. 执行摘要
    report.append("## 1. 执行摘要\n\n")
    report.append("本报告对比了VM（KVM虚拟化）和Docker容器在部署相同应用（Nginx）时的性能表现，")
    report.append("包括启动时间、资源占用、并发性能等关键指标。\n\n")
    
    # 2. 测试环境
    report.append("## 2. 测试环境\n\n")
    report.append("### 2.1 应用配置\n")
    report.append("- **测试应用**: Nginx Web服务器\n")
    report.append("- **VM类型**: KVM虚拟机（Ubuntu 22.04）\n")
    report.append("- **容器**: Docker容器（官方Nginx镜像）\n")
    report.append("- **测试工具**: Apache Bench (ab)\n\n")
    
    # 3. 性能指标对比
    report.append("## 3. 性能指标对比\n\n")
    
    # 3.1 启动时间
    vm_startup = perf_data['vm'].get('startup_time', 0)
    docker_startup = perf_data['docker'].get('startup_time', 0)
    startup_improvement = calculate_improvement(vm_startup, docker_startup, higher_is_better=False)
    
    report.append("### 3.1 启动时间对比\n\n")
    report.append("| 指标 | VM (KVM) | Docker | 差异 |\n")
    report.append("|------|----------|--------|------|\n")
    report.append(f"| 启动时间 | {vm_startup:.2f} 秒 | {docker_startup:.2f} 秒 | ")
    if startup_improvement > 0:
        report.append(f"Docker快 {startup_improvement:.1f}% |\n")
    else:
        report.append(f"VM快 {abs(startup_improvement):.1f}% |\n")
    report.append("\n**分析**: ")
    if docker_startup < vm_startup and vm_startup > 0:
        report.append(f"Docker启动速度明显快于VM，启动时间仅为VM的 {docker_startup/vm_startup*100:.1f}%。")
        report.append("这是因为Docker容器共享宿主机内核，无需启动完整的操作系统。\n\n")
    else:
        report.append("VM启动时间较长，因为需要启动完整的操作系统内核和初始化进程。\n\n")
    
    # 3.2 内存占用
    vm_memory = perf_data['vm'].get('memory_mb', 0)
    docker_memory = perf_data['docker'].get('memory_mb', 0)
    memory_improvement = calculate_improvement(vm_memory, docker_memory, higher_is_better=False)
    
    report.append("### 3.2 内存占用对比\n\n")
    report.append("| 指标 | VM (KVM) | Docker | 差异 |\n")
    report.append("|------|----------|--------|------|\n")
    report.append(f"| 内存使用 | {vm_memory:.1f} MB | {docker_memory:.1f} MB | ")
    if memory_improvement > 0:
        report.append(f"Docker节省 {memory_improvement:.1f}% |\n")
    else:
        report.append(f"VM多使用 {abs(memory_improvement):.1f}% |\n")
    report.append("\n**分析**: ")
    if docker_memory < vm_memory and vm_memory > 0:
        report.append(f"Docker内存占用更少，仅为VM的 {docker_memory/vm_memory*100:.1f}%。")
        report.append("容器共享宿主机内核，不需要为每个容器运行完整的操作系统，因此内存开销更小。\n\n")
    else:
        report.append("VM需要为每个实例运行完整的操作系统，内存开销较大。\n\n")
    
    # 3.3 磁盘占用
    vm_disk = perf_data['vm'].get('disk_bytes', 0)
    docker_disk = perf_data['docker'].get('disk_bytes', 0)
    disk_improvement = calculate_improvement(vm_disk, docker_disk, higher_is_better=False)
    
    report.append("### 3.3 磁盘占用对比\n\n")
    report.append("| 指标 | VM (KVM) | Docker | 差异 |\n")
    report.append("|------|----------|--------|------|\n")
    report.append(f"| 磁盘占用 | {format_bytes(vm_disk)} | {format_bytes(docker_disk)} | ")
    if disk_improvement > 0:
        report.append(f"Docker节省 {disk_improvement:.1f}% |\n")
    else:
        report.append(f"VM多占用 {abs(disk_improvement):.1f}% |\n")
    report.append("\n**分析**: ")
    if docker_disk < vm_disk and vm_disk > 0:
        report.append(f"Docker镜像通常比VM镜像小得多，磁盘占用仅为VM的 {docker_disk/vm_disk*100:.1f}%。")
        report.append("Docker使用分层文件系统，可以共享基础镜像层，减少存储空间。\n\n")
    else:
        report.append("VM需要完整的操作系统镜像，磁盘占用较大。\n\n")
    
    # 3.4 并发性能（压测结果）
    if stress_data['vm'] or stress_data['docker']:
        report.append("### 3.4 并发性能对比（压测结果）\n\n")
        report.append("| 指标 | VM (KVM) | Docker | 差异 |\n")
        report.append("|------|----------|--------|------|\n")
        
        vm_qps = stress_data['vm'].get('qps', 0)
        docker_qps = stress_data['docker'].get('qps', 0)
        qps_improvement = calculate_improvement(vm_qps, docker_qps, higher_is_better=True)
        
        report.append(f"| QPS (每秒请求数) | {vm_qps:.0f} | {docker_qps:.0f} | ")
        if qps_improvement > 0:
            report.append(f"Docker高 {qps_improvement:.1f}% |\n")
        else:
            report.append(f"VM高 {abs(qps_improvement):.1f}% |\n")
        
        vm_rt = stress_data['vm'].get('avg_response_time', 0)
        docker_rt = stress_data['docker'].get('avg_response_time', 0)
        
        report.append(f"| 平均响应时间 | {vm_rt:.2f} ms | {docker_rt:.2f} ms | ")
        if docker_rt < vm_rt and vm_rt > 0:
            report.append(f"Docker快 {((vm_rt-docker_rt)/vm_rt*100):.1f}% |\n")
        elif docker_rt > vm_rt and docker_rt > 0:
            report.append(f"VM快 {((docker_rt-vm_rt)/docker_rt*100):.1f}% |\n")
        else:
            report.append("数据不足，无法比较 |\n")
        
        report.append("\n**分析**: ")
        if docker_qps > vm_qps:
            report.append("Docker在并发性能上通常表现更好，因为容器化应用的系统调用开销更小，")
            report.append("没有虚拟化层的额外开销。\n\n")
        else:
            report.append("VM和Docker在并发性能上可能接近，具体取决于虚拟化技术和硬件配置。\n\n")
    
    # 4. 隔离边界分析
    report.append("## 4. 隔离边界技术差异分析\n\n")
    
    report.append("### 4.1 内核隔离\n\n")
    report.append("- **VM (KVM)**: ")
    report.append("每个VM运行独立的操作系统内核，完全的内核隔离。")
    report.append("不同VM可以使用不同的操作系统和内核版本。")
    report.append("内核级别的安全隔离，一个VM的内核崩溃不会影响其他VM。\n\n")
    
    report.append("- **Docker**: ")
    report.append("所有容器共享宿主机内核，没有内核隔离。")
    report.append("所有容器必须使用相同的内核版本（宿主机内核）。")
    report.append("内核级别的安全风险：如果内核有漏洞，可能影响所有容器。\n\n")
    
    report.append("### 4.2 文件系统隔离\n\n")
    report.append("- **VM (KVM)**: ")
    report.append("每个VM有独立的虚拟磁盘，完全的文件系统隔离。")
    report.append("可以使用不同的文件系统类型（ext4, xfs, btrfs等）。")
    report.append("文件系统级别的安全隔离。\n\n")
    
    report.append("- **Docker**: ")
    report.append("使用联合文件系统（UnionFS），容器层叠加在镜像层之上。")
    report.append("所有容器共享基础镜像层，节省存储空间。")
    report.append("文件系统隔离通过命名空间实现，但共享底层存储。\n\n")
    
    report.append("### 4.3 网络隔离\n\n")
    report.append("- **VM (KVM)**: ")
    report.append("每个VM有独立的虚拟网卡，可以通过虚拟交换机连接。")
    report.append("支持完整的网络隔离和复杂的网络拓扑。")
    report.append("可以使用不同的网络协议栈配置。\n\n")
    
    report.append("- **Docker**: ")
    report.append("使用Docker网络命名空间，每个容器有独立的网络栈。")
    report.append("可以通过Docker网络（bridge, overlay等）实现容器间通信。")
    report.append("网络隔离通过Linux网络命名空间实现。\n\n")
    
    # 5. 关键发现
    report.append("## 5. 关键发现\n\n")
    
    findings = []
    
    if docker_startup < vm_startup:
        findings.append(f"- **启动速度**: Docker启动速度比VM快 {startup_improvement:.1f}%，适合需要快速弹性伸缩的场景")
    
    if docker_memory < vm_memory:
        findings.append(f"- **资源效率**: Docker内存占用比VM少 {memory_improvement:.1f}%，可以在相同硬件上运行更多实例")
    
    if docker_disk < vm_disk:
        findings.append(f"- **存储效率**: Docker磁盘占用比VM少 {disk_improvement:.1f}%，节省存储成本")
    
    if stress_data.get('docker', {}).get('qps', 0) > stress_data.get('vm', {}).get('qps', 0):
        findings.append("- **并发性能**: Docker在并发处理能力上表现更好，适合高并发Web应用")
    
    findings.append("- **隔离性**: VM提供更强的隔离性，适合多租户环境和安全要求高的场景")
    findings.append("- **灵活性**: VM支持不同操作系统，Docker更适合微服务和DevOps场景")
    
    for finding in findings:
        report.append(f"{finding}\n")
    report.append("\n")
    
    # 6. 适用场景建议
    report.append("## 6. 适用场景建议\n\n")
    
    report.append("### 6.1 选择VM的场景\n\n")
    report.append("- 需要运行不同操作系统的应用\n")
    report.append("- 对安全隔离要求极高的多租户环境\n")
    report.append("- 需要完整操作系统功能的传统应用\n")
    report.append("- 需要独立内核配置的场景\n")
    report.append("- 合规性要求需要完全隔离的环境\n\n")
    
    report.append("### 6.2 选择Docker的场景\n\n")
    report.append("- 微服务架构和云原生应用\n")
    report.append("- 需要快速部署和弹性伸缩的场景\n")
    report.append("- 资源受限的环境（需要更高的资源利用率）\n")
    report.append("- DevOps和CI/CD流水线\n")
    report.append("- 开发、测试、生产环境一致性要求\n\n")
    
    # 7. 弹性伸缩场景分析
    report.append("## 7. 弹性伸缩场景分析\n\n")
    
    report.append("在弹性伸缩场景中，两种技术的表现：\n\n")
    
    report.append("### 7.1 启动速度对弹性伸缩的影响\n\n")
    report.append(f"- **VM**: 启动时间约 {vm_startup:.2f} 秒，在需要快速扩容时可能成为瓶颈\n")
    report.append(f"- **Docker**: 启动时间约 {docker_startup:.2f} 秒，可以快速响应流量峰值\n")
    report.append(f"- **优势**: Docker在弹性伸缩场景中响应速度更快，可以更快地应对流量变化\n\n")
    
    report.append("### 7.2 资源密度对弹性伸缩的影响\n\n")
    report.append(f"- **VM**: 每个实例占用约 {vm_memory:.1f} MB内存，{format_bytes(vm_disk)} 磁盘\n")
    report.append(f"- **Docker**: 每个实例占用约 {docker_memory:.1f} MB内存，{format_bytes(docker_disk)} 磁盘\n")
    if docker_memory < vm_memory:
        density_ratio = vm_memory / docker_memory if docker_memory > 0 else 1
        report.append(f"- **优势**: 在相同硬件上，Docker可以运行约 {density_ratio:.1f} 倍数量的实例\n\n")
    
    report.append("### 7.3 总结\n\n")
    report.append("在弹性伸缩场景中，Docker具有明显优势：\n")
    report.append("1. **快速启动**: 可以秒级启动新实例，快速响应流量变化\n")
    report.append("2. **高密度**: 可以在相同硬件上运行更多实例，提高资源利用率\n")
    report.append("3. **轻量级**: 资源占用小，降低扩容成本\n")
    report.append("4. **自动化**: 更容易实现自动化的弹性伸缩策略\n\n")
    
    report.append("VM在弹性伸缩场景中的优势：\n")
    report.append("1. **强隔离**: 适合多租户环境，不同租户需要完全隔离\n")
    report.append("2. **稳定性**: 单个实例故障不会影响其他实例\n")
    report.append("3. **兼容性**: 支持传统应用，无需改造\n\n")
    
    # 8. 结论
    report.append("## 8. 结论\n\n")
    report.append("通过本次实验对比，可以得出以下结论：\n\n")
    report.append("1. **性能方面**: Docker在启动速度、资源占用方面明显优于VM，但在隔离性方面VM更强\n")
    report.append("2. **适用场景**: Docker更适合云原生、微服务、弹性伸缩场景；VM更适合传统应用、强隔离需求场景\n")
    report.append("3. **技术选择**: 应根据具体业务需求、安全要求、资源约束来选择合适的技术\n")
    report.append("4. **混合使用**: 在实际生产环境中，VM和Docker可以混合使用，发挥各自优势\n\n")
    
    report.append("---\n\n")
    report.append("*本报告由自动化脚本生成，数据来源于实际测试结果*\n")
    
    # 写入文件
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(''.join(report))
    
    print(f"✓ 分析报告已生成: {output_file}")


def main():
    parser = argparse.ArgumentParser(description='实验结果分析')
    parser.add_argument('--vm-dir', required=True, help='VM测试结果目录')
    parser.add_argument('--docker-dir', required=True, help='Docker测试结果目录')
    parser.add_argument('--stress-dir', required=True, help='压测结果目录')
    parser.add_argument('--output-file', required=True, help='输出报告文件路径')
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("开始分析实验结果...")
    print("=" * 60)
    
    # 加载数据
    print("\n[1/2] 加载测试数据...")
    perf_data = load_performance_data(args.vm_dir, args.docker_dir)
    stress_data = load_stress_data(args.stress_dir)
    
    print("\n[2/2] 生成分析报告...")
    generate_report(perf_data, stress_data, args.output_file)
    
    print("\n" + "=" * 60)
    print("分析完成！")
    print("=" * 60)


if __name__ == '__main__':
    main()

