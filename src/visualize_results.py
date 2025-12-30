#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""VM vs Docker性能对比图表生成工具"""

import argparse
import os
import sys
import logging
from pathlib import Path
from typing import List

import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

from utils import setup_logging, ensure_dir_exists


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


def plot_performance(perf_df, out_dir):
    """使用 Plotly 绘制性能对比图表"""
    fig = make_subplots(
        rows=2, cols=2,
        subplot_titles=("启动时间对比 (s)", "CPU 占用 (%)", "内存占用 (MB)", "磁盘占用 (MB)")
    )

    metrics = [
        ("startup_time_sec", 1, 1),
        ("cpu_percent", 1, 2),
        ("memory_mb", 2, 1),
        ("disk_mb", 2, 2)
    ]

    colors = ["#4ECDC4", "#FF6B6B"]

    for i, (col, row, c) in enumerate(metrics):
        fig.add_trace(
            go.Bar(
                x=perf_df["platform"],
                y=perf_df[col],
                name=col,
                marker_color=colors,
                text=perf_df[col].apply(lambda x: f"{x:.2f}"),
                textposition='auto',
                showlegend=False
            ),
            row=row, col=c
        )

    fig.update_layout(
        title_text="VM vs Docker 资源对比 (交互式图表)",
        height=800,
        width=1000,
        template="plotly_white"
    )

    output_path = Path(out_dir) / "performance_comparison.html"
    fig.write_html(str(output_path))
    # 确保文件可读
    try:
        os.chmod(output_path, 0o644)
    except:
        pass
    print(f"✓ 性能图表: {output_path}")


def plot_stress(stress_df, out_dir):
    """使用 Plotly 绘制压测结果对比图表"""
    fig = make_subplots(
        rows=1, cols=2,
        subplot_titles=("压测 QPS (每秒请求数)", "平均延迟 (ms)")
    )

    fig.add_trace(
        go.Bar(
            x=stress_df["platform"],
            y=stress_df["qps"],
            name="QPS",
            marker_color=["#4ECDC4", "#FF6B6B"],
            text=stress_df["qps"].apply(lambda x: f"{x:.0f}"),
            textposition='auto',
            showlegend=False
        ),
        row=1, col=1
    )

    fig.add_trace(
        go.Bar(
            x=stress_df["platform"],
            y=stress_df["avg_latency_ms"],
            name="延迟",
            marker_color=["#95E1D3", "#F38181"],
            text=stress_df["avg_latency_ms"].apply(lambda x: f"{x:.2f}ms"),
            textposition='auto',
            showlegend=False
        ),
        row=1, col=2
    )

    fig.update_layout(
        title_text="压测结果对比 (交互式图表)",
        height=500,
        width=1000,
        template="plotly_white"
    )

    output_path = Path(out_dir) / "stress_comparison.html"
    fig.write_html(str(output_path))
    # 确保文件可读
    try:
        os.chmod(output_path, 0o644)
    except:
        pass
    print(f"✓ 压测图表: {output_path}")


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="生成性能与压测对比图表 (HTML版)")
    parser.add_argument("--performance-csv", required=True, help="performance.csv路径")
    parser.add_argument("--stress-csv", required=True, help="stress.csv路径")
    parser.add_argument("--output-dir", default="./results/visualization", help="输出目录")
    parser.add_argument("--verbose", "-v", action="store_true", help="详细日志")
    args = parser.parse_args()

    setup_logging(args.verbose)

    try:
        ensure_dir_exists(args.output_dir)
        
        perf_df = load_csv(args.performance_csv, 
            ["platform", "startup_time_sec", "cpu_percent", "memory_mb", "disk_mb"])
        stress_df = load_csv(args.stress_csv, 
            ["platform", "qps", "avg_latency_ms", "failed", "transfer_kbps"])

        plot_performance(perf_df, args.output_dir)
        plot_stress(stress_df, args.output_dir)
        
        print(f"\n✓ 图表已保存到: {args.output_dir} (请使用浏览器打开 .html 文件)")
    except Exception as e:
        logging.error(f"错误: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()


if __name__ == "__main__":
    main()

