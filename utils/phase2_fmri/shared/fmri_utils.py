#!/usr/bin/env python3
"""fMRI 相关的通用小工具函数。

这里集中放 ROI 标签读取、mask 读取、运动参数处理、
FD 计算以及 confounds 构建等复用逻辑。
"""

import csv
from pathlib import Path

import nibabel as nib
import numpy as np


def load_labels(path: Path):
    """读取 ROI 索引与名称，优先使用统一 label 列。"""
    indices = []
    names = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            indices.append(int(row["index"]))
            label_name = row.get("label") or row.get("name") or ""
            names.append(label_name.strip())
    return indices, names


def load_mask(path: str, shape):
    """读取 mask 并检查空间尺寸是否匹配。"""
    if not path:
        return None
    mask = np.asarray(nib.load(path).dataobj, dtype=np.float32)
    if mask.shape != shape:
        raise ValueError(f"Mask shape mismatch: {path}")
    return mask > 0.5


def extract_roi_timeseries(func, atlas, roi_indices):
    """按 ROI 标签编号提取平均时序。"""
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
    """读取 6 参数运动文件，并统一成 [TransX, TransY, TransZ, RotX, RotY, RotZ]。

    FSL mcflirt 的 .par 默认列顺序是：
    [RotX, RotY, RotZ, TransX, TransY, TransZ]
    其中旋转单位为弧度，平移单位为毫米。
    这里显式重排，避免后续绘图和 FD 计算把列顺序用反。
    """
    rp = np.loadtxt(path, dtype=float, ndmin=2)
    if rp.shape[1] < 6 and rp.shape[0] == 6:
        # np.loadtxt returns a single-row mcflirt .par as 1D unless ndmin is
        # used consistently; keep this guard for legacy callers/files.
        rp = rp.reshape(1, 6)
    if rp.shape[1] < 6:
        raise ValueError(f"Motion file must have at least 6 columns: {path}")
    rp = rp[:, :6]
    if rp.shape[0] != n_tp:
        n = min(n_tp, rp.shape[0])
        rp = rp[:n]
    return np.column_stack([rp[:, 3], rp[:, 4], rp[:, 5], rp[:, 0], rp[:, 1], rp[:, 2]])


def power_fd(rp):
    """按 Power FD 定义计算逐帧 FD。

    输入 rp 必须采用内部统一顺序：
    [TransX, TransY, TransZ, RotX, RotY, RotZ]
    其中旋转仍保持弧度单位，再乘以 50 mm 头半径换算成位移。
    """
    dif = np.vstack([np.zeros((1, 6), dtype=float), np.diff(rp, axis=0)])
    trans = np.abs(dif[:, :3])
    rot = np.abs(dif[:, 3:]) * 50.0
    return np.sum(np.hstack([trans, rot]), axis=1)


def build_motion_confounds(rp, hm_model):
    """按照 6/12/24/36 模型构建运动 confounds。"""
    if hm_model == 6:
        return rp
    dif = np.vstack([np.zeros((1, 6), dtype=float), np.diff(rp, axis=0)])
    if hm_model == 12:
        return np.hstack([rp, dif])
    if hm_model in (24, 36):
        return np.hstack([rp, dif, rp**2, dif**2])
    raise ValueError(f"Unsupported hm model: {hm_model}")


def build_signal_confounds(signal):
    """为单个生理信号构建原值、导数、平方项。"""
    signal = np.asarray(signal, dtype=float).reshape(-1)
    dif = np.concatenate([[0.0], np.diff(signal)])
    return np.column_stack([signal, dif, signal**2, dif**2])


def zscore_cols(x):
    """按列做 z-score，零方差列直接置零。"""
    out = x.copy().astype(float)
    for i in range(out.shape[1]):
        std = out[:, i].std(ddof=0)
        if std > 1e-8:
            out[:, i] = (out[:, i] - out[:, i].mean()) / std
        else:
            out[:, i] = 0.0
    return out
