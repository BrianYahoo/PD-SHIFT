#!/usr/bin/env python3
"""对比不同 radial search 参数下的结构连接矩阵。

该脚本读取两张同尺寸矩阵：
- 主流程矩阵：assignment_radial_search = 2
- 对比矩阵：assignment_radial_search = 4

输出一张对比图：
- 左侧两张热图分别展示两张矩阵
- 右侧展示非对角元素的一一对应散点回归图
"""

import argparse
from pathlib import Path

import matplotlib

# 使用无界面后端，保证服务器环境下也能正常出图。
matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import seaborn as sns
from scipy.stats import pearsonr


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix-main", required=True)
    parser.add_argument("--matrix-compare", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--main-label", default="radial=2")
    parser.add_argument("--compare-label", default="radial=4")
    return parser.parse_args()


def load_matrix(path: str) -> np.ndarray:
    """读取 CSV 矩阵并检查其为二维方阵。"""
    matrix = np.loadtxt(path, delimiter=",", dtype=float)
    if matrix.ndim != 2 or matrix.shape[0] != matrix.shape[1]:
        raise ValueError(f"Matrix must be square: {path}")
    return matrix


def off_diagonal_values(matrix: np.ndarray) -> np.ndarray:
    """提取非对角元素，按上三角顺序展开。"""
    tri = np.triu_indices(matrix.shape[0], k=1)
    return matrix[tri]


def main():
    """绘制热图与非对角元素回归对比图。"""
    args = parse_args()
    main_matrix = load_matrix(args.matrix_main)
    compare_matrix = load_matrix(args.matrix_compare)

    if main_matrix.shape != compare_matrix.shape:
        raise ValueError("Input matrices must have the same shape")

    main_vals = off_diagonal_values(main_matrix)
    compare_vals = off_diagonal_values(compare_matrix)
    valid = np.isfinite(main_vals) & np.isfinite(compare_vals)
    x = main_vals[valid]
    y = compare_vals[valid]

    if x.size == 0:
        raise ValueError("No valid off-diagonal values found for comparison")

    corr, _ = pearsonr(x, y)

    # 统一颜色范围，方便直接比较两张矩阵。
    v_abs = float(np.nanmax(np.abs(np.concatenate([main_matrix.ravel(), compare_matrix.ravel()]))))
    vmin = -v_abs
    vmax = v_abs
    if v_abs == 0.0:
        vmin, vmax = -1.0, 1.0

    sns.set_theme(style="white")
    fig = plt.figure(figsize=(18, 6), dpi=200)
    gs = fig.add_gridspec(1, 3, width_ratios=[1, 1, 1.15], wspace=0.28)

    ax1 = fig.add_subplot(gs[0, 0])
    ax2 = fig.add_subplot(gs[0, 1])
    ax3 = fig.add_subplot(gs[0, 2])

    sns.heatmap(
        main_matrix,
        ax=ax1,
        cmap="RdBu_r",
        center=0,
        vmin=vmin,
        vmax=vmax,
        square=True,
        cbar=True,
        xticklabels=False,
        yticklabels=False,
    )
    ax1.set_title(args.main_label)

    sns.heatmap(
        compare_matrix,
        ax=ax2,
        cmap="RdBu_r",
        center=0,
        vmin=vmin,
        vmax=vmax,
        square=True,
        cbar=True,
        xticklabels=False,
        yticklabels=False,
    )
    ax2.set_title(args.compare_label)

    sns.regplot(
        x=x,
        y=y,
        ax=ax3,
        scatter_kws={"s": 10, "alpha": 0.28, "edgecolor": "none"},
        line_kws={"color": "#c23b22", "linewidth": 2},
        ci=None,
    )
    lim_min = float(np.nanmin(np.concatenate([x, y])))
    lim_max = float(np.nanmax(np.concatenate([x, y])))
    if lim_min == lim_max:
        lim_min -= 1.0
        lim_max += 1.0
    ax3.plot([lim_min, lim_max], [lim_min, lim_max], linestyle="--", color="0.4", linewidth=1)
    ax3.set_xlim(lim_min, lim_max)
    ax3.set_ylim(lim_min, lim_max)
    ax3.set_xlabel(args.main_label)
    ax3.set_ylabel(args.compare_label)
    ax3.set_title(f"Off-diagonal comparison\nr = {corr:.4f}, n = {x.size}")

    fig.suptitle("Connectome radial search comparison", fontsize=15)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(output_path, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    main()
