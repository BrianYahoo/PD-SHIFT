#!/usr/bin/env python3
"""批量重绘已有的 motion_metrics.png。

不重跑任何 shell step，只遍历现有 workspace 中已经生成过的
phase2_fmri motion 可视化目录，并用最新绘图逻辑覆盖 PNG 与 FD 文件。
"""

from __future__ import annotations

import argparse
from pathlib import Path

from fmri_utils import load_motion, power_fd

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--roots",
        nargs="+",
        default=[
            "/data/bryang/project/CNS/data/HCP/workspace",
            "/data/bryang/project/CNS/data/Parkinson/workspace",
        ],
    )
    parser.add_argument("--fd-threshold", type=float, default=0.5)
    return parser.parse_args()


def draw_motion_plot(motion_path: Path, png_path: Path, fd_path: Path, fd_threshold: float):
    raw = np.loadtxt(motion_path, dtype=float)
    if raw.ndim == 1:
        raw = raw[:, None]
    n_tp = raw.shape[0]
    motion = load_motion(str(motion_path), n_tp)
    fd = power_fd(motion)
    rotation_deg = np.rad2deg(motion[:, 3:])
    np.savetxt(fd_path, fd, fmt="%.8f")

    fig, axes = plt.subplots(3, 1, figsize=(12, 8), dpi=150, sharex=True)
    x = np.arange(n_tp)

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
    axes[2].axhline(fd_threshold, color="red", linestyle="--", linewidth=1.0, label=f"FD={fd_threshold:.2f}")
    axes[2].set_xlabel("Frame")
    axes[2].set_ylabel("FD (mm)")
    axes[2].set_title("Power FD (mm)")
    axes[2].legend(loc="upper right", fontsize=8)

    for ax in axes:
        ax.grid(True, alpha=0.2)

    fig.tight_layout()
    png_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(png_path, bbox_inches="tight")
    plt.close(fig)


def iter_motion_dirs(root: Path):
    pattern = "*/derivatives/cns-pipeline/sub-*/phases/phase2_fmri/visualization/*/motion"
    yield from root.glob(pattern)


def infer_motion_file(motion_dir: Path):
    trial_name = motion_dir.parent.name
    phase2_dir = motion_dir.parents[2]
    motion_path = phase2_dir / trial_name / "func_mc.par"
    return motion_path if motion_path.exists() else None


def main():
    args = parse_args()
    updated = 0
    skipped = 0

    for root_str in args.roots:
        root = Path(root_str)
        if not root.exists():
            continue
        for motion_dir in iter_motion_dirs(root):
            motion_path = infer_motion_file(motion_dir)
            if motion_path is None:
                skipped += 1
                continue
            png_path = motion_dir / "motion_metrics.png"
            fd_path = motion_dir / "framewise_displacement.tsv"
            draw_motion_plot(motion_path, png_path, fd_path, args.fd_threshold)
            updated += 1
            print(f"updated\t{png_path}")

    print(f"updated_total\t{updated}")
    print(f"skipped_total\t{skipped}")


if __name__ == "__main__":
    main()
