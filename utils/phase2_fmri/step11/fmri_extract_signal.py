#!/usr/bin/env python3
"""用 NiftiLabelsMasker 提取 ROI 时序并计算 FC。

该脚本读取最终干净的 4D fMRI 与已经投到 func space 的 atlas，
输出 ROI 时序、Pearson FC、Fisher-z FC 和对应 QC 信息。
"""

import argparse
import json
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
import pandas as pd
from nilearn.maskers import NiftiLabelsMasker

UTILS_ROOT = Path(__file__).resolve().parents[2]
if str(UTILS_ROOT) not in sys.path:
    sys.path.insert(0, str(UTILS_ROOT))

from phase2_fmri.shared.fmri_utils import load_labels


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--func", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--labels", required=True)
    parser.add_argument("--output-matrix", required=True)
    parser.add_argument("--output-z", required=True)
    parser.add_argument("--output-timeseries", required=True)
    parser.add_argument("--output-qc", required=True)
    parser.add_argument("--scrub-qc", default="")
    parser.add_argument("--regress-qc", default="")
    parser.add_argument("--detrend-qc", default="")
    parser.add_argument("--filter-qc", default="")
    return parser.parse_args()


def corr_and_z(ts):
    """根据 ROI x T 时序矩阵计算相关矩阵与 Fisher-z 矩阵。"""
    ts = np.asarray(ts, dtype=np.float64)
    n_roi, n_tp = ts.shape
    corr = np.zeros((n_roi, n_roi), dtype=np.float64)
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


def load_optional_json(path: str):
    """如果附加 QC 文件存在，则一并读入。"""
    if not path:
        return {}
    p = Path(path)
    if not p.exists():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def main():
    """执行 ROI 时序提取并写出 FC 结果。"""
    args = parse_args()
    func_img = nib.load(args.func)
    atlas_img = nib.load(args.atlas)
    atlas = np.asarray(atlas_img.dataobj, dtype=np.int32)

    roi_indices, roi_names = load_labels(Path(args.labels))
    # 直接利用 Nilearn 的标签 masker，在当前 atlas 标签顺序下提取 ROI 时序。
    masker = NiftiLabelsMasker(
        labels_img=atlas_img,
        background_label=0,
        strategy="mean",
        standardize=False,
    )
    present_ts = masker.fit_transform(func_img)
    # Nilearn 会自动丢掉 atlas 中不存在的标签。为了保证后续矩阵始终严格按 roi.tsv 的 88 ROI 顺序输出，
    # 这里需要把缺失 ROI 重新补成全 0 列，而不是直接接受少列结果。
    present_region_ids = []
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
            f"Nilearn output columns do not match detected atlas labels: "
            f"{present_ts.shape[1]} vs {len(present_region_ids)}"
        )

    roi_index_to_col = {int(idx): col for col, idx in enumerate(roi_indices)}
    ts = np.zeros((present_ts.shape[0], len(roi_indices)), dtype=np.float32)
    dropped_labels = []
    for col_idx, roi_idx in enumerate(present_region_ids):
        target_col = roi_index_to_col.get(int(roi_idx))
        if target_col is None:
            dropped_labels.append(int(roi_idx))
            continue
        ts[:, target_col] = present_ts[:, col_idx]

    corr, zmat = corr_and_z(ts.T)
    pd.DataFrame(corr).to_csv(args.output_matrix, header=False, index=False, float_format="%.8f")
    pd.DataFrame(zmat).to_csv(args.output_z, header=False, index=False, float_format="%.8f")
    pd.DataFrame(ts, columns=roi_names).to_csv(args.output_timeseries, sep="\t", index=False, float_format="%.8f")

    voxel_counts = {name: int(np.count_nonzero(atlas == idx)) for idx, name in zip(roi_indices, roi_names)}
    missing_roi_indices = [int(idx) for idx, name in zip(roi_indices, roi_names) if voxel_counts[name] == 0]
    missing_roi_labels = [name for idx, name in zip(roi_indices, roi_names) if voxel_counts[name] == 0]
    qc = {
        "backend": "nilearn.maskers.NiftiLabelsMasker",
        "n_rois": len(roi_names),
        "n_timepoints_final": int(ts.shape[0]),
        "n_present_rois_in_atlas": int(len(present_region_ids)),
        "roi_voxel_counts": voxel_counts,
        "missing_roi_indices": missing_roi_indices,
        "missing_roi_labels": missing_roi_labels,
        "atlas_labels_without_master_mapping": dropped_labels,
        "scrub": load_optional_json(args.scrub_qc),
        "regress": load_optional_json(args.regress_qc),
        "detrend": load_optional_json(args.detrend_qc),
        "filter": load_optional_json(args.filter_qc),
    }
    Path(args.output_qc).write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
