# VM vs Docker 性能对比实验

## 快速开始

```bash
# 进入项目目录
cd src

# 一键运行完整实验
bash run_experiment.sh
```

## 实验内容

本实验对比VMWare虚拟机和Docker容器的性能差异，包括：

- **启动时间**：测量服务启动速度
- **资源占用**：CPU、内存、磁盘使用情况
- **并发性能**：压力测试QPS和响应时间
- **可视化对比**：自动生成性能对比图表

## 环境要求

- **操作系统**：Ubuntu 20.04+, Debian 11+, CentOS 7+
- **权限**：需要sudo权限
- **网络**：需要互联网连接（首次运行）
- **硬件**：建议2+核CPU，4GB+内存

## 主要脚本

| 脚本 | 说明 |
|------|------|
| `run_experiment.sh` | 主运行脚本，执行完整实验流程 |
| `vm_test.sh` | VM虚拟机性能测试 |
| `docker_test.sh` | Docker容器性能测试 |
| `stress_test.sh` | 压力测试对比 |
| `install_dependencies.sh` | 自动安装所有依赖 |
| `cleanup.sh` | 清理实验环境 |
| `port_manager.sh` | 端口管理工具 |

## 命令选项

```bash
# 完整运行（包含依赖安装）
bash run_experiment.sh

# 跳过依赖安装
bash run_experiment.sh --skip-deps

# 指定其他端口
bash run_experiment.sh --port 9090

# 自动选择可用端口
bash run_experiment.sh --auto-port

# 查看帮助
bash run_experiment.sh --help
```

## 端口配置

默认使用端口8080。如果被占用，可以：

```bash
# 方式1：自动选择端口
bash run_experiment.sh --auto-port

# 方式2：指定端口
bash run_experiment.sh --port 9090

# 方式3：环境变量
export APP_PORT=9090
bash run_experiment.sh

# 方式4：使用端口管理工具
bash port_manager.sh check 8080    # 检查端口
bash port_manager.sh info 8080     # 查看占用进程
bash port_manager.sh find 8080     # 查找可用端口
```

## 结果输出

实验完成后，结果保存在 `results/` 目录：

```
results/
├── performance.csv           # 性能对比数据
├── stress.csv                # 压测数据
├── visualization/            # 交互式可视化图表 (HTML)
│   ├── performance_comparison.html
│   └── stress_comparison.html
├── analysis_report.md        # 自动生成的详细分析报告
├── vm/                       # VM测试详细数据
└── docker/                   # Docker测试详细数据
```

## 清理环境

```bash
bash cleanup.sh
```

## 常见问题

### 端口被占用？
```bash
bash run_experiment.sh --auto-port
```

### Docker权限不足？
```bash
sudo usermod -aG docker $USER
# 重新登录或运行
newgrp docker
```

### Python包缺失？
```bash
bash install_dependencies.sh
```

## 实验流程

1. **安装依赖** → 2. **VM测试** → 3. **Docker测试** → 4. **压力测试** → 5. **生成图表**

## 许可证

本项目用于云计算课程期末大作业。

