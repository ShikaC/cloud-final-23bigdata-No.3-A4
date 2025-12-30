#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# 公共工具模块
# =============================================================================
# 提供通用的工具函数，供其他脚本使用
# =============================================================================

import os
import sys
import logging
from pathlib import Path
from typing import Any, Union


def setup_logging(verbose: bool = False) -> None:
    """配置日志系统
    
    Args:
        verbose: 是否显示详细日志（DEBUG级别）
    """
    log_level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )


def validate_file_exists(filepath: Union[str, Path], 
                        file_desc: str = "文件") -> Path:
    """验证文件是否存在
    
    Args:
        filepath: 文件路径
        file_desc: 文件描述（用于错误消息）
        
    Returns:
        Path对象
        
    Raises:
        SystemExit: 文件不存在时退出
    """
    path = Path(filepath)
    if not path.exists():
        logging.error(f"{file_desc}不存在: {filepath}")
        sys.exit(1)
    if not path.is_file():
        logging.error(f"{filepath} 不是一个文件")
        sys.exit(1)
    return path


def validate_dir_exists(dirpath: Union[str, Path], 
                       dir_desc: str = "目录") -> Path:
    """验证目录是否存在
    
    Args:
        dirpath: 目录路径
        dir_desc: 目录描述（用于错误消息）
        
    Returns:
        Path对象
        
    Raises:
        SystemExit: 目录不存在时退出
    """
    path = Path(dirpath)
    if not path.exists():
        logging.error(f"{dir_desc}不存在: {dirpath}")
        sys.exit(1)
    if not path.is_dir():
        logging.error(f"{dirpath} 不是一个目录")
        sys.exit(1)
    return path


def ensure_dir_exists(dirpath: Union[str, Path]) -> Path:
    """确保目录存在，不存在则创建
    
    Args:
        dirpath: 目录路径
        
    Returns:
        Path对象
    """
    path = Path(dirpath)
    path.mkdir(parents=True, exist_ok=True)
    return path


def read_file_content(filepath: Union[str, Path], default: str = "0") -> str:
    """读取文件内容
    
    Args:
        filepath: 文件路径
        default: 文件不存在或读取失败时的默认值
        
    Returns:
        文件内容或默认值
    """
    try:
        path = Path(filepath)
        if path.exists():
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                return content if content else default
        logging.debug(f"文件不存在: {path}")
        return default
    except Exception as e:
        logging.warning(f"读取文件失败 {filepath}: {e}")
        return default


def safe_float_parse(value: Any, default: float = 0.0) -> float:
    """安全地将值转换为浮点数
    
    Args:
        value: 要转换的值
        default: 转换失败时的默认值
        
    Returns:
        转换后的浮点数或默认值
    """
    try:
        # 移除常见的单位
        value_str = str(value).strip()
        for unit in ['MB', 'GB', 'KB', 'B', '%', 'ms', 's']:
            value_str = value_str.replace(unit, '')
        return float(value_str)
    except (ValueError, TypeError, AttributeError):
        logging.debug(f"无法将 '{value}' 转换为浮点数，使用默认值 {default}")
        return default


def format_size(bytes_value: Union[int, float], 
               decimal_places: int = 2) -> str:
    """格式化字节数为人类可读格式
    
    Args:
        bytes_value: 字节数
        decimal_places: 小数位数
        
    Returns:
        格式化后的字符串（如 "1.50 MB"）
    """
    try:
        value = float(bytes_value)
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if value < 1024.0:
                return f"{value:.{decimal_places}f} {unit}"
            value /= 1024.0
        return f"{value:.{decimal_places}f} PB"
    except (ValueError, TypeError):
        return str(bytes_value)


def print_section_header(title: str, width: int = 60, char: str = "=") -> None:
    """打印章节标题
    
    Args:
        title: 标题文本
        width: 总宽度
        char: 装饰字符
    """
    print(char * width)
    print(title)
    print(char * width)


def print_progress(message: str, step: int = 0, total: int = 0) -> None:
    """打印进度信息
    
    Args:
        message: 消息内容
        step: 当前步骤（可选）
        total: 总步骤数（可选）
    """
    if step > 0 and total > 0:
        print(f"\n[{step}/{total}] {message}")
    else:
        print(f"\n{message}")

