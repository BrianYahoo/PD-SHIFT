#!/usr/bin/env python3
"""把图谱叠加到底图像空间，并输出逐层 PNG 可视化。

支持三维底图，也支持四维底图中指定若干时间点。
当提供 labels.tsv 时，会对皮层下脑区使用更高的不透明度，
以便更直观看到 STN、GPi、SN 等深部结构的配准精度。
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
    parser.add_argument("--base", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--labels-tsv", default="")
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--frames", default="")
    parser.add_argument("--frame-label", default="")
    parser.add_argument("--variant-subdir", default="")
    parser.add_argument("--split-subdirs", action="store_true")
    parser.add_argument("--cortical-alpha", type=float, default=0.35)
    parser.add_argument("--subcortical-alpha", type=float, default=0.60)
    return parser.parse_args()


def normalize_base(slice2d: np.ndarray) -> np.ndarray:
    """把底图切片拉到 0-1，便于稳定显示。"""
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


def load_subcortical_indices(labels_tsv: str) -> set[int]:
    """从 labels.tsv 中读取皮层下脑区编号。"""
    if not labels_tsv:
        return set()

    subcortical = set()
    with Path(labels_tsv).open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            source = (row.get("source") or "").strip().lower()
            if source == "subcortical":
                subcortical.add(int(row["index"]))
    return subcortical


def load_label_map(labels_tsv: str) -> dict[str, int]:
    """读取 labels.tsv，建立 label -> atlas index 映射。"""
    if not labels_tsv:
        return {}
    out: dict[str, int] = {}
    with Path(labels_tsv).open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            label = (row.get("label") or "").strip()
            if label:
                out[label] = int(row["index"])
    return out


def build_subcortex_target_map(label_map: dict[str, int]) -> dict[str, tuple[int, int]]:
    """把 10 类皮层下脑区映射为左右标签 index。"""
    out: dict[str, tuple[int, int]] = {}
    for folder_name, (left_label, right_label) in SUBCORTEX_GROUPS:
        if left_label in label_map and right_label in label_map:
            out[folder_name] = (label_map[left_label], label_map[right_label])
    return out


def parse_frames(frame_text: str, n_tp: int) -> list[int]:
    """解析需要输出的时间点列表。"""
    if n_tp <= 1:
        return [0]
    if not frame_text.strip():
        return [0]

    frames = []
    for token in frame_text.split(","):
        token = token.strip()
        if not token:
            continue
        frame = int(token)
        if 0 <= frame < n_tp:
            frames.append(frame)
    return sorted(set(frames)) or [0]


def build_alpha(overlay: np.ndarray, subcortical_indices: set[int], cortical_alpha: float, subcortical_alpha: float) -> np.ndarray:
    """按照皮层/皮层下标签构造不同透明度的 alpha 图。"""
    alpha = np.zeros_like(overlay, dtype=np.float32)
    alpha[overlay > 0] = cortical_alpha
    if subcortical_indices:
        for idx in subcortical_indices:
            alpha[overlay == idx] = subcortical_alpha
    return alpha


def save_one_panel(base2d: np.ndarray, atlas2d: np.ndarray, subcortical_indices: set[int], out_png: Path, cortical_alpha: float, subcortical_alpha: float, title: str):
    """输出单张叠加 PNG。"""
    base = np.rot90(normalize_base(base2d))
    overlay = np.rot90(atlas2d.astype(np.int32))
    alpha = np.rot90(build_alpha(atlas2d.astype(np.int32), subcortical_indices, cortical_alpha, subcortical_alpha))

    fig, ax = plt.subplots(figsize=(6, 6), dpi=150)
    ax.imshow(base, cmap="gray", interpolation="nearest")
    ax.imshow(overlay, cmap="tab20", interpolation="nearest", alpha=alpha, vmin=0)
    ax.set_title(title, fontsize=10)
    ax.axis("off")
    fig.tight_layout(pad=0.1)
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_png, bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)


def save_subcortex_focus(
    base2d: np.ndarray,
    atlas2d: np.ndarray,
    left_idx: int,
    right_idx: int,
    out_png: Path,
    title: str,
):
    """输出单个皮层下结构左右半球的高对比度 overlay。"""
    base = np.rot90(normalize_base(base2d))
    overlay = np.rot90(atlas2d.astype(np.int32))

    fig, ax = plt.subplots(figsize=(6, 6), dpi=150)
    ax.imshow(base, cmap="gray", interpolation="nearest")

    background_alpha = np.where(overlay > 0, 0.10, 0.0)
    ax.imshow(overlay, cmap=plt.get_cmap("tab20"), interpolation="nearest", alpha=background_alpha, vmin=0)

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
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_png, bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)


def main():
    """执行逐层 overlay 可视化。"""
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    base_img = nib.load(args.base)
    atlas_img = nib.load(args.atlas)
    # 如果图谱和底图不在同一空间，先用最近邻重采样。
    if base_img.shape[:3] != atlas_img.shape[:3] or not np.allclose(base_img.affine, atlas_img.affine):
        atlas_img = resample_from_to(atlas_img, base_img, order=0)

    base = np.asarray(base_img.dataobj, dtype=np.float32)
    atlas = np.asarray(atlas_img.dataobj, dtype=np.int32)
    if atlas.ndim != 3:
        raise ValueError("Atlas must be a 3D label image")

    subcortical_indices = load_subcortical_indices(args.labels_tsv)
    subcortex_targets = build_subcortex_target_map(load_label_map(args.labels_tsv))

    if base.ndim == 3:
        frames = [0]
    elif base.ndim == 4:
        frames = parse_frames(args.frames, base.shape[3])
    else:
        raise ValueError("Base image must be 3D or 4D")

    for frame_idx in frames:
        if base.ndim == 4:
            frame_dir = out_dir / f"t={frame_idx}"
            frame_data = base[:, :, :, frame_idx]
        else:
            frame_dir = out_dir / args.frame_label if args.frame_label else out_dir
            frame_data = base
        if args.variant_subdir:
            frame_dir = frame_dir / args.variant_subdir

        if args.split_subdirs:
            for folder_name in subcortex_targets:
                focus_dir = frame_dir / "subcortex" / folder_name
                if focus_dir.exists():
                    for stale_png in focus_dir.glob("z=*.png"):
                        stale_png.unlink()

        for z_idx in range(frame_data.shape[2]):
            atlas_dir = frame_dir / "atlas" if args.split_subdirs else frame_dir
            save_one_panel(
                frame_data[:, :, z_idx],
                atlas[:, :, z_idx],
                subcortical_indices,
                atlas_dir / f"z={z_idx}.png",
                args.cortical_alpha,
                args.subcortical_alpha,
                f"z={z_idx}" if base.ndim == 3 else f"t={frame_idx}, z={z_idx}",
            )
            if args.split_subdirs:
                for folder_name, (left_idx, right_idx) in subcortex_targets.items():
                    if not np.any((atlas[:, :, z_idx] == left_idx) | (atlas[:, :, z_idx] == right_idx)):
                        continue
                    save_subcortex_focus(
                        frame_data[:, :, z_idx],
                        atlas[:, :, z_idx],
                        left_idx,
                        right_idx,
                        frame_dir / "subcortex" / folder_name / f"z={z_idx}.png",
                        f"{folder_name}, z={z_idx}" if base.ndim == 3 else f"{folder_name}, t={frame_idx}, z={z_idx}",
                    )


if __name__ == "__main__":
    main()
