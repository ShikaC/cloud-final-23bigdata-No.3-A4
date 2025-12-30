#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""VM vs Docker性能对比图表生成工具"""

import argparse
import os
import sys
import logging
import warnings
from pathlib import Path
from typing import List, Optional

import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import seaborn as sns

# 抑制matplotlib的字体警告
warnings.filterwarnings('ignore', category=UserWarning, module='matplotlib')
warnings.filterwarnings('ignore', category=FutureWarning, module='seaborn')


def load_csv(path: str, required_cols: List[str]) -> pd.DataFrame:
    """加载CSV文件并验证"""
    if not Path(path).exists():
        raise FileNotFoundError(f"文件不存在: {path}")
    
    df = pd.read_csv(path)
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"{path} 缺少必需的列: {missing}")
    
    logging.debug(f"加载 {path}: {len(df)} 行")
    return df


def ensure_chinese_font() -> None:
    """确保中文字体可用"""
    import matplotlib.font_manager as fm
    
    # WSL/Linux环境常见字体路径
    font_paths = [
        "/mnt/c/Windows/Fonts/msyh.ttc",        # 微软雅黑 (WSL)
        "/mnt/c/Windows/Fonts/simhei.ttf",      # 黑体 (WSL)
        "/mnt/c/Windows/Fonts/simsun.ttc",      # 宋体 (WSL)
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",  # 文泉驿微米黑
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",    # 文泉驿正黑
        "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",  # Droid
    ]
    
    # 尝试加载字体文件
    for font_path in font_paths:
        if os.path.exists(font_path):
            try:
                fm.fontManager.addfont(font_path)
                font_name = fm.FontProperties(fname=font_path).get_name()
                plt.rcParams['font.sans-serif'] = [font_name, 'DejaVu Sans']
                plt.rcParams['axes.unicode_minus'] = False
                logging.debug(f"成功加载中文字体: {font_name}")
                return
            except Exception as e:
                logging.debug(f"加载字体失败 {font_path}: {e}")
    
    # 尝试使用系统字体
    font_names = ['Microsoft YaHei', 'SimHei', 'WenQuanYi Micro Hei', 
                  'Noto Sans CJK SC', 'Source Han Sans CN', 'Arial Unicode MS']
    available_fonts = set(f.name for f in fm.fontManager.ttflist)
    
    for font_name in font_names:
        if font_name in available_fonts:
            plt.rcParams['font.sans-serif'] = [font_name, 'DejaVu Sans']
            plt.rcParams['axes.unicode_minus'] = False
            logging.debug(f"使用系统字体: {font_name}")
            return
    
    # 使用DejaVu Sans作为后备（虽然不支持中文，但不会报错）
    plt.rcParams['font.sans-serif'] = ['DejaVu Sans']
    plt.rcParams['axes.unicode_minus'] = False
    logging.debug("未找到中文字体，使用默认字体")


def bar(ax, df, x, y, title, ylabel, fmt="{:.2f}", palette=None):
    """绘制柱状图"""
    palette = palette or ["#4ECDC4", "#FF6B6B"]
    # 修复seaborn警告：将x映射到hue并设置legend=False
    bars = sns.barplot(ax=ax, data=df, x=x, y=y, hue=x, palette=palette, legend=False)
    
    for patch, val in zip(bars.patches, df[y].tolist()):
        height = patch.get_height()
        if height > 0:
            ax.text(patch.get_x() + patch.get_width() / 2, height,
                   fmt.format(val), ha="center", va="bottom", fontsize=10, fontweight="bold")
    
    ax.set_title(title, fontsize=12, fontweight="bold")
    ax.set_ylabel(ylabel)
    ax.set_xlabel("")
    ax.grid(axis="y", alpha=0.2)


def plot_performance(perf_df, out_dir):
    """绘制性能对比图表"""
    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    bar(axes[0, 0], perf_df, "platform", "startup_time_sec", "启动时间对比", "秒", "{:.2f}")
    bar(axes[0, 1], perf_df, "platform", "cpu_percent", "CPU 占用", "%", "{:.1f}%")
    bar(axes[1, 0], perf_df, "platform", "memory_mb", "内存占用", "MB", "{:.1f}")
    bar(axes[1, 1], perf_df, "platform", "disk_mb", "磁盘占用", "MB", "{:.1f}")
    
    fig.suptitle("VM vs Docker 资源对比", fontsize=14, fontweight="bold")
    fig.tight_layout()
    
    output_path = Path(out_dir) / "performance_comparison.png"
    fig.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close(fig)
    print(f"✓ 性能图表: {output_path}")


def plot_stress(stress_df, out_dir):
    """绘制压测结果对比图表"""
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    bar(axes[0], stress_df, "platform", "qps", "压测 QPS", "每秒请求数", "{:.0f}")
    bar(axes[1], stress_df, "platform", "avg_latency_ms", "平均延迟", "毫秒", 
        "{:.1f}ms", palette=["#95E1D3", "#F38181"])
    
    fig.suptitle("压测结果对比", fontsize=14, fontweight="bold")
    fig.tight_layout()
    
    output_path = Path(out_dir) / "stress_comparison.png"
    fig.savefig(output_path, dpi=300, bbox_inches='tight')
    plt.close(fig)
    print(f"✓ 压测图表: {output_path}")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="生成性能与压测对比图表")
    parser.add_argument("--performance-csv", required=True, help="performance.csv路径")
    parser.add_argument("--stress-csv", required=True, help="stress.csv路径")
    parser.add_argument("--output-dir", default="./results/visualization", help="输出目录")
    parser.add_argument("--verbose", "-v", action="store_true", help="详细日志")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format='%(levelname)s: %(message)s'
    )

    try:
        os.makedirs(args.output_dir, exist_ok=True)
        
        ensure_chinese_font()
        sns.set_style("whitegrid")

        perf_df = load_csv(args.performance_csv, 
            ["platform", "startup_time_sec", "cpu_percent", "memory_mb", "disk_mb"])
        stress_df = load_csv(args.stress_csv, 
            ["platform", "qps", "avg_latency_ms", "failed", "transfer_kbps"])

        plot_performance(perf_df, args.output_dir)
        plot_stress(stress_df, args.output_dir)
        
        print(f"\n✓ 图表已保存到: {args.output_dir}")
    except Exception as e:
        logging.error(f"错误: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

