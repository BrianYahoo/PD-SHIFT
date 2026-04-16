#!/usr/bin/env python3

"""把个体 T1 与最终 hybrid atlas 叠加可视化，并按 z 轴逐层输出 PNG。

这个脚本用于 phase1_anat/step6 之后的人工快速核对。
输出分两部分：
1. atlas 总览：灰度 T1 + 半透明全 atlas 叠加。
2. subcortex 细看：按 10 类皮层下脑区分别输出，仅对该脑区的左右半球做高对比度高亮，
   其余脑区保持较淡颜色，方便观察边界与覆盖情况。
"""

import argparse
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to


SUBCORTEX_GROUPS = [
    ("CER", ("L.CER", "R.CER")),
    ("TH", ("L.TH", "R.TH")),
    ("CA", ("L.CA", "R.CA")),
    ("PU", ("L.PU", "R.PU")),
    ("HI", ("L.HI", "R.HI")),
    ("AC", ("L.AC", "R.AC")),
    ("GPe", ("L.GPe", "R.GPe")),
    ("GPi", ("L.GPi", "R.GPi")),
    ("STN", ("L.STN", "R.STN")),
    ("SNc", ("L.SNc", "R.SNc")),
]

LEFT_HIGHLIGHT = np.array([0.16, 0.45, 0.95], dtype=np.float32)
RIGHT_HIGHLIGHT = np.array([0.92, 0.28, 0.20], dtype=np.float32)


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--t1", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--labels-tsv", required=True)
    parser.add_argument("--atlas-out-dir", required=True)
    parser.add_argument("--subcortex-out-dir", required=True)
    return parser.parse_args()


def normalize_base(slice2d: np.ndarray) -> np.ndarray:
    """把 T1 切片拉到 0-1，便于稳定显示。"""
    data = slice2d.astype(np.float32)
    finite = np.isfinite(data)
    if not np.any(finite):
        return np.zeros_like(data, dtype=np.float32)
    vals = data[finite]
    low = np.percentile(vals, 1)
    high = np.percentile(vals, 99)
    if high <= low:
        return np.zeros_like(data, dtype=np.float32)
    out = np.clip((data - low) / (high - low), 0.0, 1.0)
    out[~finite] = 0.0
    return out


def load_label_map(path: Path) -> dict[str, int]:
    """读取最终 atlas labels.tsv，建立统一标签到 index 的映射。"""
    out: dict[str, int] = {}
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            label = row.get("label", "").strip()
            if not label:
                continue
            out[label] = int(row["index"])
    return out


def build_subcortex_target_map(label_map: dict[str, int]) -> dict[str, tuple[int, int]]:
    """把 10 类皮层下脑区映射为左/右统一标签 index。"""
    out: dict[str, tuple[int, int]] = {}
    for folder_name, (left_label, right_label) in SUBCORTEX_GROUPS:
        if left_label not in label_map or right_label not in label_map:
            continue
        out[folder_name] = (label_map[left_label], label_map[right_label])
    return out


def draw_overview(base: np.ndarray, overlay: np.ndarray, out_path: Path, z_idx: int) -> None:
    """输出整张 atlas 的常规叠加图。"""
    alpha = np.where(overlay > 0, 0.35, 0.0)
    fig, ax = plt.subplots(figsize=(6, 6), dpi=150)
    ax.imshow(base, cmap="gray", interpolation="nearest")
    ax.imshow(overlay, cmap=plt.get_cmap("tab20"), interpolation="nearest", alpha=alpha, vmin=0)
    ax.set_title(f"z={z_idx}", fontsize=10)
    ax.axis("off")
    fig.tight_layout(pad=0.1)
    fig.savefig(out_path, bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)


def draw_subcortex_focus(
    base: np.ndarray,
    overlay: np.ndarray,
    left_idx: int,
    right_idx: int,
    out_path: Path,
    title: str,
) -> None:
    """输出某一类皮层下脑区的高对比度焦点图。"""
    fig, ax = plt.subplots(figsize=(6, 6), dpi=150)
    ax.imshow(base, cmap="gray", interpolation="nearest")

    # 其他 atlas 区域维持较淡颜色，便于看整体位置关系。
    background_alpha = np.where(overlay > 0, 0.10, 0.0)
    ax.imshow(overlay, cmap=plt.get_cmap("tab20"), interpolation="nearest", alpha=background_alpha, vmin=0)

    # 目标左右半球用固定高对比度颜色高亮。
    left_mask = overlay == left_idx
    right_mask = overlay == right_idx

    if np.any(left_mask):
        left_rgb = np.zeros((*overlay.shape, 4), dtype=np.float32)
        left_rgb[..., :3] = LEFT_HIGHLIGHT
        left_rgb[..., 3] = left_mask.astype(np.float32) * 0.58
        ax.imshow(left_rgb, interpolation="nearest")

    if np.any(right_mask):
        right_rgb = np.zeros((*overlay.shape, 4), dtype=np.float32)
        right_rgb[..., :3] = RIGHT_HIGHLIGHT
        right_rgb[..., 3] = right_mask.astype(np.float32) * 0.58
        ax.imshow(right_rgb, interpolation="nearest")

    ax.set_title(title, fontsize=10)
    ax.axis("off")
    fig.tight_layout(pad=0.1)
    fig.savefig(out_path, bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)


def main():
    """逐层输出 hybrid atlas 叠加图。"""
    args = parse_args()
    atlas_out_dir = Path(args.atlas_out_dir)
    subcortex_out_dir = Path(args.subcortex_out_dir)
    atlas_out_dir.mkdir(parents=True, exist_ok=True)
    subcortex_out_dir.mkdir(parents=True, exist_ok=True)

    t1_img = nib.load(args.t1)
    atlas_img = nib.load(args.atlas)
    label_map = load_label_map(Path(args.labels_tsv))
    subcortex_targets = build_subcortex_target_map(label_map)
    if t1_img.shape != atlas_img.shape or not np.allclose(t1_img.affine, atlas_img.affine):
        atlas_img = resample_from_to(atlas_img, t1_img, order=0)

    t1 = np.asarray(t1_img.dataobj, dtype=np.float32)
    atlas = np.asarray(atlas_img.dataobj, dtype=np.int32)

    for z_idx in range(t1.shape[2]):
        base = np.rot90(normalize_base(t1[:, :, z_idx]))
        overlay = np.rot90(atlas[:, :, z_idx])
        draw_overview(base, overlay, atlas_out_dir / f"z={z_idx}.png", z_idx)

        for folder_name, (left_idx, right_idx) in subcortex_targets.items():
            if not np.any((overlay == left_idx) | (overlay == right_idx)):
                continue
            focus_dir = subcortex_out_dir / folder_name
            focus_dir.mkdir(parents=True, exist_ok=True)
            draw_subcortex_focus(
                base=base,
                overlay=overlay,
                left_idx=left_idx,
                right_idx=right_idx,
                out_path=focus_dir / f"z={z_idx}.png",
                title=f"{folder_name} z={z_idx}",
            )


if __name__ == "__main__":
    main()
