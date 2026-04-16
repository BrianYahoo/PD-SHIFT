#!/usr/bin/env python3
"""为 fMRI step5-10 生成逐步 ROI 时序与 FC 诊断结果。

该脚本直接读取每一步对应的 4D 功能像，以及已经投到 func space 的 atlas，
分别输出：
1. 每一步的 ROI 时序表
2. 每一步的 Pearson / Fisher-z FC
3. 每一步的脑区信号可视化
4. 每一步的 FC 热图可视化

这是实现层的附加诊断功能，不写入 pipeline 文档主流程。
"""

import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np
import pandas as pd
from nilearn.maskers import NiftiLabelsMasker

from fmri_utils import load_labels


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--labels", required=True)
    parser.add_argument("--result-dir", required=True)
    parser.add_argument("--signal-dir", required=True)
    parser.add_argument("--fc-dir", required=True)
    parser.add_argument("--sample-rois", default="1,11,22,33,44,55,66,88")
    parser.add_argument("--sample-length", type=int, default=200)
    parser.add_argument(
        "--step-spec",
        action="append",
        default=[],
        help="格式：step_no|step_name|func_path|scrub_mask_path，scrub_mask_path 可留空",
    )
    return parser.parse_args()


def corr_and_z(ts):
    """根据 ROI x T 时序矩阵计算相关矩阵与 Fisher-z 矩阵。"""
    ts = np.asarray(ts, dtype=np.float64)
    n_roi, n_tp = ts.shape
    corr = np.zeros((n_roi, n_roi), dtype=np.float64)
    if n_tp == 0:
        return corr, corr.copy()
    centered = ts - ts.mean(axis=1, keepdims=True)
    scale = centered.std(axis=1, ddof=0)
    valid = scale > 1e-12
    if np.count_nonzero(valid) > 0:
        normalized = np.zeros_like(centered)
        normalized[valid] = centered[valid] / scale[valid, None]
        corr[np.ix_(valid, valid)] = (normalized[valid] @ normalized[valid].T) / float(n_tp)
    np.fill_diagonal(corr, 0.0)
    clipped = np.clip(corr, -0.999999, 0.999999)
    z = np.arctanh(clipped)
    np.fill_diagonal(z, 0.0)
    return corr, z


def parse_step_spec(spec):
    """解析单个 step 定义。"""
    parts = spec.split("|")
    if len(parts) != 4:
        raise ValueError(f"Invalid --step-spec: {spec}")
    step_no, step_name, func_path, scrub_mask_path = parts
    return int(step_no), step_name, Path(func_path), Path(scrub_mask_path) if scrub_mask_path else None


def extract_timeseries(func_img, atlas_img, roi_indices):
    """按固定 ROI 顺序提取时序，并补齐缺失标签。"""
    atlas = np.asarray(atlas_img.dataobj, dtype=np.int32)
    masker = NiftiLabelsMasker(
        labels_img=atlas_img,
        background_label=0,
        strategy="mean",
        standardize=None,
    )
    present_ts = masker.fit_transform(func_img)
    if hasattr(masker, "region_ids_"):
        present_region_ids = [
            int(label_value)
            for key, label_value in sorted(
                ((key, value) for key, value in masker.region_ids_.items() if key != "background"),
                key=lambda kv: int(kv[0]),
            )
        ]
    else:
        present_region_ids = sorted(int(x) for x in np.unique(atlas) if int(x) != 0)

    if present_ts.shape[1] != len(present_region_ids):
        raise ValueError(
            "Nilearn output columns do not match detected atlas labels: "
            f"{present_ts.shape[1]} vs {len(present_region_ids)}"
        )

    roi_index_to_col = {int(idx): col for col, idx in enumerate(roi_indices)}
    ts = np.zeros((present_ts.shape[0], len(roi_indices)), dtype=np.float32)
    for col_idx, roi_idx in enumerate(present_region_ids):
        target_col = roi_index_to_col.get(int(roi_idx))
        if target_col is None:
            continue
        ts[:, target_col] = present_ts[:, col_idx]
    return ts


def load_scrub_keep_mask(path, n_tp):
    """把 toxic frame 掩膜转成保留帧掩膜。"""
    if path is None or (not path.exists()):
        return np.ones(n_tp, dtype=bool), False
    toxic = np.loadtxt(path, dtype=int)
    toxic = np.atleast_1d(toxic).astype(bool)
    if toxic.shape[0] != n_tp:
      raise ValueError(f"Scrub mask length mismatch: {path}")
    keep = ~toxic
    if not np.any(keep):
        keep[:] = True
    return keep, True


def central_window_indices(n_tp, sample_length):
    """返回居中的时间窗索引。"""
    if n_tp <= sample_length:
        return np.arange(n_tp, dtype=int)
    start = max((n_tp - sample_length) // 2, 0)
    end = start + sample_length
    return np.arange(start, end, dtype=int)


def plot_signal(step_label, ts, roi_names, sample_positions, sample_length, out_png):
    """绘制指定 step 的 8 个 ROI 脑区信号图。"""
    time_idx = central_window_indices(ts.shape[0], sample_length)
    fig, axes = plt.subplots(4, 2, figsize=(14, 10), sharex=True)
    axes = axes.reshape(-1)
    for ax, roi_pos in zip(axes, sample_positions):
        col_idx = roi_pos - 1
        label = roi_names[col_idx]
        ax.plot(time_idx, ts[time_idx, col_idx], color="#1f77b4", linewidth=1.2)
        ax.set_title(f"ROI {roi_pos}: {label}", fontsize=10)
        ax.grid(alpha=0.25, linewidth=0.5)
    fig.suptitle(f"{step_label} ROI Signals", fontsize=14)
    fig.tight_layout(rect=(0, 0, 1, 0.97))
    fig.savefig(out_png, dpi=160)
    plt.close(fig)


def plot_fc(step_label, corr, out_png):
    """绘制指定 step 的 FC 热图。"""
    vmin = float(np.nanmin(corr)) if corr.size else -0.1
    vmax = float(np.nanmax(corr)) if corr.size else 0.1
    if not np.isfinite(vmin):
        vmin = -0.1
    if not np.isfinite(vmax):
        vmax = 0.1
    if vmax <= vmin:
        center = float(vmax)
        vmin = center - 0.05
        vmax = center + 0.05
    fig, ax = plt.subplots(figsize=(8, 7))
    im = ax.imshow(corr, cmap="coolwarm", vmin=vmin, vmax=vmax, interpolation="nearest")
    ax.set_title(f"{step_label} FC")
    ax.set_xlabel("ROI")
    ax.set_ylabel("ROI")
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.tight_layout()
    fig.savefig(out_png, dpi=160)
    plt.close(fig)


def plot_fc_overall(step_items, out_png):
    """把 6 个 step 的 FC 放到同一张 2x3 图里，并共享统一 colorbar。"""
    if not step_items:
        return

    matrices = [corr for _, corr in step_items]
    global_vmin = float(min(np.nanmin(corr) for corr in matrices))
    global_vmax = float(max(np.nanmax(corr) for corr in matrices))
    if not np.isfinite(global_vmin):
        global_vmin = -0.1
    if not np.isfinite(global_vmax):
        global_vmax = 0.1
    if global_vmax <= global_vmin:
        center = float(global_vmax)
        global_vmin = center - 0.05
        global_vmax = center + 0.05

    fig, axes = plt.subplots(2, 3, figsize=(15, 10))
    axes = axes.reshape(-1)
    im = None
    for ax, (step_label, corr) in zip(axes, step_items):
        im = ax.imshow(corr, cmap="coolwarm", vmin=global_vmin, vmax=global_vmax, interpolation="nearest")
        ax.set_title(step_label, fontsize=11)
        ax.set_xlabel("ROI")
        ax.set_ylabel("ROI")

    for ax in axes[len(step_items):]:
        ax.axis("off")

    if im is not None:
        cbar_ax = fig.add_axes([0.92, 0.14, 0.015, 0.72])
        fig.colorbar(im, cax=cbar_ax)
    fig.subplots_adjust(left=0.06, right=0.90, top=0.92, bottom=0.07, wspace=0.25, hspace=0.28)
    fig.savefig(out_png, dpi=160)
    plt.close(fig)


def write_outputs(step_no, step_name, ts, corr, zmat, roi_names, result_dir):
    """写出时序、FC 与 step 级 QC 文件。"""
    step_prefix = f"step{step_no}_{step_name}"
    ts_path = result_dir / f"{step_prefix}_timeseries.tsv"
    fc_path = result_dir / f"{step_prefix}_fc_pearson.csv"
    z_path = result_dir / f"{step_prefix}_fc_fisherz.csv"
    qc_path = result_dir / f"{step_prefix}_qc.json"
    pd.DataFrame(ts, columns=roi_names).to_csv(ts_path, sep="\t", index=False, float_format="%.8f")
    pd.DataFrame(corr).to_csv(fc_path, header=False, index=False, float_format="%.8f")
    pd.DataFrame(zmat).to_csv(z_path, header=False, index=False, float_format="%.8f")
    return ts_path, fc_path, z_path, qc_path


def main():
    """执行逐步信号提取、FC 计算与可视化。"""
    args = parse_args()
    atlas_img = nib.load(args.atlas)
    roi_indices, roi_names = load_labels(Path(args.labels))
    result_dir = Path(args.result_dir)
    signal_dir = Path(args.signal_dir)
    fc_dir = Path(args.fc_dir)
    result_dir.mkdir(parents=True, exist_ok=True)
    signal_dir.mkdir(parents=True, exist_ok=True)
    fc_dir.mkdir(parents=True, exist_ok=True)

    sample_positions = [int(x.strip()) for x in args.sample_rois.split(",") if x.strip()]
    for roi_pos in sample_positions:
        if roi_pos < 1 or roi_pos > len(roi_indices):
            raise ValueError(f"Sample ROI position out of range: {roi_pos}")

    summary = []
    overall_fc_items = []
    for step_spec in args.step_spec:
        step_no, step_name, func_path, scrub_mask_path = parse_step_spec(step_spec)
        if not func_path.exists():
            raise FileNotFoundError(f"Missing step input: {func_path}")

        func_img = nib.load(str(func_path))
        ts = extract_timeseries(func_img, atlas_img, roi_indices)
        keep_mask, scrub_mask_used = load_scrub_keep_mask(scrub_mask_path, ts.shape[0])
        ts_used = ts[keep_mask]
        corr, zmat = corr_and_z(ts_used.T)

        ts_path, fc_path, z_path, qc_path = write_outputs(step_no, step_name, ts_used, corr, zmat, roi_names, result_dir)
        signal_png = signal_dir / f"step{step_no}_{step_name}_signal.png"
        fc_png = fc_dir / f"step{step_no}_{step_name}_fc.png"
        plot_signal(f"Step {step_no} {step_name}", ts_used, roi_names, sample_positions, args.sample_length, signal_png)
        plot_fc(f"Step {step_no} {step_name}", corr, fc_png)
        overall_fc_items.append((f"Step {step_no} {step_name}", corr))

        qc = {
            "step_no": int(step_no),
            "step_name": step_name,
            "func_path": str(func_path),
            "scrub_mask_path": str(scrub_mask_path) if scrub_mask_path else "",
            "scrub_mask_used": bool(scrub_mask_used),
            "n_timepoints_input": int(ts.shape[0]),
            "n_timepoints_output": int(ts_used.shape[0]),
            "sample_roi_positions": sample_positions,
            "sample_roi_labels": [roi_names[pos - 1] for pos in sample_positions],
            "timeseries_tsv": str(ts_path),
            "fc_pearson_csv": str(fc_path),
            "fc_fisherz_csv": str(z_path),
            "signal_png": str(signal_png),
            "fc_png": str(fc_png),
        }
        qc_path.write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")
        summary.append(qc)

    plot_fc_overall(overall_fc_items, fc_dir / "overall.png")
    (result_dir / "manifest.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8"
    )


if __name__ == "__main__":
    main()
