#!/usr/bin/env python3
"""旧版 FC 计算脚本。

该脚本保留为参考实现，包含：
- confounds 回归
- temporal filter
- scrubbing
- ROI 时序与 FC 计算

当前主流程已经更偏向使用 Nilearn 版本工具，但这个脚本仍可作为算法参考。
"""

import argparse
import csv
import json
from pathlib import Path

import nibabel as nib
import numpy as np
import pandas as pd
from scipy.interpolate import interp1d
from scipy.signal import butter, filtfilt


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--func", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--labels", required=True)
    parser.add_argument("--tr", required=True, type=float)
    parser.add_argument("--motion", required=True)
    parser.add_argument("--wm-mask", default="")
    parser.add_argument("--csf-mask", default="")
    parser.add_argument("--gs-mask", default="")
    parser.add_argument("--hm-model", type=int, default=24)
    parser.add_argument("--regress-gs", action="store_true")
    parser.add_argument("--detrend-order", type=int, default=1)
    parser.add_argument("--low-cut", type=float, default=0.01)
    parser.add_argument("--high-cut", type=float, default=0.10)
    parser.add_argument("--fd-threshold", type=float, default=0.2)
    parser.add_argument("--scrub-before", type=int, default=1)
    parser.add_argument("--scrub-after", type=int, default=2)
    parser.add_argument("--scrub-method", default="remove", choices=["remove", "nearest", "linear", "spline"])
    parser.add_argument("--min-keep", type=int, default=30)
    parser.add_argument("--output-matrix", required=True)
    parser.add_argument("--output-z", required=True)
    parser.add_argument("--output-timeseries", required=True)
    parser.add_argument("--output-qc", required=True)
    parser.add_argument("--output-fd", required=True)
    parser.add_argument("--output-scrub-mask", required=True)
    return parser.parse_args()


def load_labels(path: Path):
    """读取 ROI 标签顺序。"""
    indices = []
    names = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            indices.append(int(row["index"]))
            names.append(row["name"].strip())
    return indices, names


def load_mask(path: str, shape):
    """读取 3D mask，并检查空间维度是否匹配。"""
    if not path:
        return None
    mask = np.asarray(nib.load(path).dataobj, dtype=np.float32)
    if mask.shape != shape:
        raise ValueError(f"Mask shape mismatch: {path}")
    return mask > 0.5


def extract_roi_timeseries(func, atlas, roi_indices):
    """按 ROI 标签逐个提取平均时序。"""
    n_tp = func.shape[3]
    func_flat = func.reshape((-1, n_tp))
    atlas_flat = atlas.reshape(-1)
    ts = []
    counts = []
    for idx in roi_indices:
        mask = atlas_flat == idx
        counts.append(int(np.count_nonzero(mask)))
        if counts[-1] == 0:
            ts.append(np.full(n_tp, np.nan, dtype=float))
        else:
            ts.append(func_flat[mask].mean(axis=0))
    return np.asarray(ts, dtype=float), counts


def mean_signal(func, mask):
    """计算给定 mask 内的平均时序。"""
    if mask is None:
        return None
    n_tp = func.shape[3]
    flat = func.reshape((-1, n_tp))
    mflat = mask.reshape(-1)
    if np.count_nonzero(mflat) == 0:
        return None
    return flat[mflat].mean(axis=0)


def load_motion(path: str, n_tp: int):
    """读取 mcflirt 运动参数，并重排为 [TransX, TransY, TransZ, RotX, RotY, RotZ]。"""
    rp = np.loadtxt(path, dtype=float, ndmin=2)
    if rp.shape[1] < 6 and rp.shape[0] == 6:
        rp = rp.reshape(1, 6)
    if rp.shape[1] < 6:
        raise ValueError(f"Motion file must have at least 6 columns: {path}")
    rp = rp[:, :6]
    if rp.shape[0] != n_tp:
        n = min(n_tp, rp.shape[0])
        rp = rp[:n]
    return np.column_stack([rp[:, 3], rp[:, 4], rp[:, 5], rp[:, 0], rp[:, 1], rp[:, 2]])


def power_fd(rp):
    """按 Power FD 计算逐帧 FD，输入顺序为 [Trans, Rot]。"""
    dif = np.vstack([np.zeros((1, 6), dtype=float), np.diff(rp, axis=0)])
    trans = np.abs(dif[:, :3])
    rot = np.abs(dif[:, 3:]) * 50.0
    return np.sum(np.hstack([trans, rot]), axis=1)


def build_motion_confounds(rp, hm_model):
    if hm_model == 6:
        return rp
    dif = np.vstack([np.zeros((1, 6), dtype=float), np.diff(rp, axis=0)])
    if hm_model == 12:
        return np.hstack([rp, dif])
    if hm_model in (24, 36):
        return np.hstack([rp, dif, rp**2, dif**2])
    raise ValueError(f"Unsupported hm model: {hm_model}")


def build_signal_confounds(signal):
    signal = np.asarray(signal, dtype=float).reshape(-1)
    dif = np.concatenate([[0.0], np.diff(signal)])
    return np.column_stack([signal, dif, signal**2, dif**2])


def zscore_cols(x):
    out = x.copy().astype(float)
    for i in range(out.shape[1]):
        std = out[:, i].std(ddof=0)
        if std > 1e-8:
            out[:, i] = (out[:, i] - out[:, i].mean()) / std
        else:
            out[:, i] = 0.0
    return out


def detrend(ts, order):
    if order < 0:
        return ts
    n_tp = ts.shape[1]
    x = np.linspace(-1.0, 1.0, n_tp)
    design = [np.ones(n_tp, dtype=float)]
    for o in range(1, order + 1):
        design.append(x**o)
    design = np.column_stack(design)
    if design.shape[1] > 1:
        design[:, 1:] = zscore_cols(design[:, 1:])
    pinv = np.linalg.pinv(design)
    out = ts.copy()
    for i in range(out.shape[0]):
        if np.any(~np.isfinite(out[i])):
            continue
        out[i] = out[i] - design @ (pinv @ out[i])
    return out


def regress(ts, confounds):
    if confounds.size == 0:
        return ts
    design = np.column_stack([np.ones(confounds.shape[0], dtype=float), confounds])
    pinv = np.linalg.pinv(design)
    out = ts.copy()
    for i in range(out.shape[0]):
        if np.any(~np.isfinite(out[i])):
            continue
        out[i] = out[i] - design @ (pinv @ out[i])
    return out


def temporal_filter(ts, tr, low_cut, high_cut):
    n_tp = ts.shape[1]
    if n_tp < 30:
        return ts
    nyq = 0.5 / tr
    low = low_cut / nyq if low_cut > 0 else 0
    high = high_cut / nyq if high_cut > 0 else 0
    if not (0 < low < high < 1):
        return ts
    b, a = butter(2, [low, high], btype="bandpass")
    out = ts.copy()
    for i in range(out.shape[0]):
        if np.any(~np.isfinite(out[i])):
            continue
        out[i] = filtfilt(b, a, out[i])
    return out


def build_scrub_mask(fd, threshold, before, after):
    bad = np.zeros(fd.shape[0], dtype=bool)
    base = np.where(fd > threshold)[0]
    bad[base] = True
    for step in range(1, before + 1):
        idx = base - step
        idx = idx[idx >= 0]
        bad[idx] = True
    for step in range(1, after + 1):
        idx = base + step
        idx = idx[idx < fd.shape[0]]
        bad[idx] = True
    return bad


def interpolate_bad(ts, bad, method):
    keep = ~bad
    x = np.arange(ts.shape[1], dtype=float)
    x_keep = x[keep]
    if x_keep.size < 2:
        return ts
    interp_kind = "cubic" if method == "spline" and x_keep.size >= 4 else method
    out = ts.copy()
    for i in range(out.shape[0]):
        if np.any(~np.isfinite(out[i])):
            continue
        func = interp1d(
            x_keep,
            out[i, keep],
            kind=interp_kind,
            bounds_error=False,
            fill_value=(float(out[i, keep][0]), float(out[i, keep][-1])),
            assume_sorted=True,
        )
        out[i] = func(x)
    return out


def corr_and_z(ts):
    corr = np.corrcoef(ts)
    corr = np.nan_to_num(corr, nan=0.0)
    np.fill_diagonal(corr, 0.0)
    clipped = np.clip(corr, -0.999999, 0.999999)
    z = np.arctanh(clipped)
    np.fill_diagonal(z, 0.0)
    return corr, z


def main():
    args = parse_args()
    func_img = nib.load(args.func)
    atlas_img = nib.load(args.atlas)

    func = np.asarray(func_img.dataobj, dtype=np.float32)
    atlas = np.asarray(atlas_img.dataobj, dtype=np.int32)

    roi_indices, roi_names = load_labels(Path(args.labels))
    ts, voxel_counts = extract_roi_timeseries(func, atlas, roi_indices)

    wm = mean_signal(func, load_mask(args.wm_mask, atlas.shape))
    csf = mean_signal(func, load_mask(args.csf_mask, atlas.shape))
    gs = mean_signal(func, load_mask(args.gs_mask, atlas.shape))
    motion = load_motion(args.motion, ts.shape[1])
    fd = power_fd(motion)
    confounds = [build_motion_confounds(motion, args.hm_model)]
    if args.hm_model == 36:
        missing = []
        if wm is None:
            missing.append("wm")
        if csf is None:
            missing.append("csf")
        if gs is None:
            missing.append("gs")
        if missing:
            raise ValueError(f"HM model 36 requires wm/csf/gs signals, missing: {','.join(missing)}")
        confounds.append(build_signal_confounds(wm))
        confounds.append(build_signal_confounds(csf))
        confounds.append(build_signal_confounds(gs))
    else:
        if wm is not None:
            confounds.append(np.column_stack([wm]))
        if csf is not None:
            confounds.append(np.column_stack([csf]))
        if args.regress_gs and gs is not None:
            confounds.append(np.column_stack([gs]))

    confounds = np.hstack(confounds)
    confounds = zscore_cols(confounds)

    ts = detrend(ts, args.detrend_order)
    ts = regress(ts, confounds)
    ts = temporal_filter(ts, args.tr, args.low_cut, args.high_cut)

    scrub_bad = build_scrub_mask(fd, args.fd_threshold, args.scrub_before, args.scrub_after)
    if args.scrub_method == "remove":
        keep = ~scrub_bad
        if int(np.count_nonzero(keep)) >= args.min_keep:
            ts = ts[:, keep]
        else:
            keep = np.ones_like(scrub_bad, dtype=bool)
        scrub_mask = keep.astype(int)
    else:
        ts = interpolate_bad(ts, scrub_bad, args.scrub_method)
        scrub_mask = (~scrub_bad).astype(int)

    corr, zmat = corr_and_z(ts)

    pd.DataFrame(corr).to_csv(args.output_matrix, header=False, index=False, float_format="%.8f")
    pd.DataFrame(zmat).to_csv(args.output_z, header=False, index=False, float_format="%.8f")
    pd.DataFrame(ts.T, columns=roi_names).to_csv(args.output_timeseries, sep="\t", index=False, float_format="%.8f")
    np.savetxt(args.output_fd, fd, fmt="%.8f")
    np.savetxt(args.output_scrub_mask, scrub_mask, fmt="%d")

    qc = {
        "n_rois": len(roi_names),
        "n_timepoints_final": int(ts.shape[1]),
        "tr": float(args.tr),
        "hm_model": int(args.hm_model),
        "n_confounds": int(confounds.shape[1]),
        "fd_mean": float(np.mean(fd)),
        "fd_max": float(np.max(fd)),
        "scrub_bad_count": int(np.count_nonzero(scrub_bad)),
        "roi_voxel_counts": {name: int(count) for name, count in zip(roi_names, voxel_counts)},
    }
    Path(args.output_qc).write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
