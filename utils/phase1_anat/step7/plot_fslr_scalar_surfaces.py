#!/usr/bin/env python3
"""把左右半球 fsLR 标量 metric 画成四视图皮层表面图。"""

import argparse
import os
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np

# 在无头服务器上优先使用离屏渲染，并把 VTK 警告关掉，避免批跑时刷满日志。
os.environ.setdefault("PYVISTA_OFF_SCREEN", "true")
os.environ.setdefault("PYVISTA_USE_IPYVTK", "false")

import vtk
from brainspace.mesh.mesh_io import read_surface
from surfplot import Plot

vtk.vtkObject.GlobalWarningDisplayOff()


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--left-surface", required=True)
    parser.add_argument("--right-surface", required=True)
    parser.add_argument("--left-metric", required=True)
    parser.add_argument("--right-metric", required=True)
    parser.add_argument("--left-bg", default="")
    parser.add_argument("--right-bg", default="")
    parser.add_argument("--title", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--cmap", default="viridis")
    return parser.parse_args()


def load_gifti_data(path: str):
    img = nib.load(path)
    if not hasattr(img, "darrays") or not img.darrays:
        raise RuntimeError(f"Unsupported GIFTI data: {path}")
    return np.asarray(img.darrays[0].data, dtype=np.float32)


def finite_percentiles(values: np.ndarray):
    finite = values[np.isfinite(values)]
    if finite.size == 0:
        return 0.0, 1.0
    nonzero = finite[np.abs(finite) > 1.0e-8]
    if nonzero.size:
        finite = nonzero
    vmin = float(np.percentile(finite, 2))
    vmax = float(np.percentile(finite, 98))
    if vmax <= vmin:
        vmax = vmin + 1.0
    return vmin, vmax


def build_layer_dict(left: np.ndarray, right: np.ndarray):
    return {"left": np.asarray(left, dtype=np.float32), "right": np.asarray(right, dtype=np.float32)}


def main():
    args = parse_args()

    left_metric = load_gifti_data(args.left_metric)
    right_metric = load_gifti_data(args.right_metric)
    merged = np.concatenate([left_metric, right_metric])
    vmin, vmax = finite_percentiles(merged)

    surf_l = read_surface(args.left_surface)
    surf_r = read_surface(args.right_surface)

    plot = Plot(
        surf_l,
        surf_r,
        views=["lateral", "medial"],
        size=(900, 700),
        zoom=1.25,
        brightness=0.7,
        background=(1, 1, 1),
    )

    if args.left_bg and args.right_bg:
        left_bg = load_gifti_data(args.left_bg)
        right_bg = load_gifti_data(args.right_bg)
        bg_vmin, bg_vmax = finite_percentiles(np.concatenate([left_bg, right_bg]))
        plot.add_layer(
            build_layer_dict(left_bg, right_bg),
            cmap="gray",
            alpha=0.55,
            cbar=False,
            color_range=(bg_vmin, bg_vmax),
            zero_transparent=False,
        )

    plot.add_layer(
        build_layer_dict(left_metric, right_metric),
        cmap=args.cmap,
        alpha=0.95,
        cbar=True,
        color_range=(vmin, vmax),
        zero_transparent=False,
    )

    fig = plot.build(figsize=(10.5, 8.2), colorbar=True)
    fig.suptitle(args.title, fontsize=18, y=0.98)
    fig.subplots_adjust(left=0.02, right=0.98, bottom=0.06, top=0.94, wspace=0.02, hspace=0.02)

    Path(args.output).parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.output, dpi=300, bbox_inches="tight", facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    main()
