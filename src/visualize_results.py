#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# 读取 performance.csv 与 stress.csv 生成对比图表
# 输出目录：--output-dir (默认 ./results/visualization)
# =============================================================================

import argparse
import os
from pathlib import Path
import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import seaborn as sns  # noqa: E402


def load_csv(path, required_cols):
    df = pd.read_csv(path)
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"{path} 缺少列: {missing}")
    return df


def ensure_chinese_font():
    import matplotlib.font_manager as fm
    import os

    candidates = [
        "SimHei",
        "Microsoft YaHei",
        "WenQuanYi Micro Hei",
        "Noto Sans CJK SC",
        "Source Han Sans CN",
    ]

    # 额外尝试从常见路径加载字体（含 WSL 访问 Windows 字体）
    extra_paths = [
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        "/mnt/c/Windows/Fonts/simhei.ttf",
        "/mnt/c/Windows/Fonts/msyh.ttc",
    ]
    for p in extra_paths:
        if os.path.exists(p):
            try:
                fm.fontManager.addfont(p)
            except Exception:
                pass

    available = [f.name for f in fm.fontManager.ttflist]
    for name in candidates:
        if name in available:
            plt.rcParams["font.family"] = name
            break
    plt.rcParams["axes.unicode_minus"] = False


def bar(ax, df, x, y, title, ylabel, fmt="{:.2f}", palette=None):
    palette = palette or ["#4ECDC4", "#FF6B6B"]
    bars = sns.barplot(ax=ax, data=df, x=x, y=y, palette=palette)
    for patch, val in zip(bars.patches, df[y].tolist()):
        ax.text(
            patch.get_x() + patch.get_width() / 2,
            patch.get_height(),
            fmt.format(val),
            ha="center",
            va="bottom",
            fontsize=10,
            fontweight="bold",
        )
    ax.set_title(title, fontsize=12, fontweight="bold")
    ax.set_ylabel(ylabel)
    ax.grid(axis="y", alpha=0.2)


def plot_performance(perf_df, out_dir):
    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    bar(axes[0, 0], perf_df, "platform", "startup_time_sec", "启动时间对比", "秒", "{:.2f}")
    bar(axes[0, 1], perf_df, "platform", "cpu_percent", "CPU 占用", "%", "{:.1f}%")
    bar(axes[1, 0], perf_df, "platform", "memory_mb", "内存占用", "MB", "{:.1f}")
    bar(axes[1, 1], perf_df, "platform", "disk_mb", "磁盘占用", "MB", "{:.1f}")
    fig.suptitle("KVM vs Docker 资源对比", fontsize=14, fontweight="bold")
    fig.tight_layout()
    path = Path(out_dir) / "performance_comparison.png"
    fig.savefig(path, dpi=300)
    plt.close(fig)
    print(f"✓ 性能图表: {path}")


def plot_stress(stress_df, out_dir):
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    bar(axes[0], stress_df, "platform", "qps", "压测 QPS", "每秒请求数", "{:.0f}")
    bar(
        axes[1],
        stress_df,
        "platform",
        "avg_latency_ms",
        "平均延迟",
        "毫秒",
        "{:.1f}ms",
        palette=["#95E1D3", "#F38181"],
    )
    fig.suptitle("压测结果对比", fontsize=14, fontweight="bold")
    fig.tight_layout()
    path = Path(out_dir) / "stress_comparison.png"
    fig.savefig(path, dpi=300)
    plt.close(fig)
    print(f"✓ 压测图表: {path}")


def main():
    parser = argparse.ArgumentParser(description="生成性能与压测对比图表")
    parser.add_argument("--performance-csv", required=True, help="performance.csv 路径")
    parser.add_argument("--stress-csv", required=True, help="stress.csv 路径")
    parser.add_argument("--output-dir", default="./results/visualization", help="输出目录")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)
    ensure_chinese_font()
    sns.set_style("whitegrid")

    perf_df = load_csv(args.performance_csv, ["platform", "startup_time_sec", "cpu_percent", "memory_mb", "disk_mb"])
    stress_df = load_csv(args.stress_csv, ["platform", "qps", "avg_latency_ms", "failed", "transfer_kbps"])

    plot_performance(perf_df, args.output_dir)
    plot_stress(stress_df, args.output_dir)
    print(f"所有图表已输出到: {args.output_dir}")


if __name__ == "__main__":
    main()

