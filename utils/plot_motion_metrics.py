#!/usr/bin/env python3
"""绘制头动参数与 FD 指标图。

输入为 mcflirt 输出的 6 参数运动文件。
内部会先把原始列顺序 [Rot, Trans] 重排成 [Trans, Rot]，
再输出一张 PNG，总览平移、旋转以及 Power FD。
"""

import argparse
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from fmri_utils import load_motion, power_fd


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--motion", required=True)
    parser.add_argument("--fd-threshold", type=float, default=0.5)
    parser.add_argument("--output-png", required=True)
    parser.add_argument("--output-fd", required=True)
    return parser.parse_args()


def main():
    """绘制 motion / FD 指标图。"""
    args = parse_args()
    raw = np.loadtxt(args.motion, dtype=float, ndmin=2)
    n_tp = raw.shape[0]
    motion = load_motion(args.motion, n_tp)
    fd = power_fd(motion)
    np.savetxt(args.output_fd, fd, fmt="%.8f")
    rotation_deg = np.rad2deg(motion[:, 3:])

    fig, axes = plt.subplots(3, 1, figsize=(12, 8), dpi=150, sharex=True)
    x = np.arange(motion.shape[0])

    axes[0].plot(x, motion[:, 0], label="X")
    axes[0].plot(x, motion[:, 1], label="Y")
    axes[0].plot(x, motion[:, 2], label="Z")
    axes[0].set_ylabel("Translation (mm)")
    axes[0].set_title("Head Motion: Translation (mm)")
    axes[0].legend(loc="upper right", ncol=3, fontsize=8)

    axes[1].plot(x, rotation_deg[:, 0], label="RotX")
    axes[1].plot(x, rotation_deg[:, 1], label="RotY")
    axes[1].plot(x, rotation_deg[:, 2], label="RotZ")
    axes[1].set_ylabel("Rotation (degree)")
    axes[1].set_title("Head Motion: Rotation (degree)")
    axes[1].legend(loc="upper right", ncol=3, fontsize=8)

    axes[2].plot(x, fd, color="black", linewidth=1.0, label="FD")
    axes[2].axhline(args.fd_threshold, color="red", linestyle="--", linewidth=1.0, label=f"FD={args.fd_threshold:.2f}")
    axes[2].set_xlabel("Frame")
    axes[2].set_ylabel("FD (mm)")
    axes[2].set_title("Power FD (mm)")
    axes[2].legend(loc="upper right", fontsize=8)

    for ax in axes:
      ax.grid(True, alpha=0.2)

    fig.tight_layout()
    out_path = Path(args.output_png)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    main()
