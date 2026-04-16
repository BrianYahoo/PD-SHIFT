#!/usr/bin/env python3
"""执行 fMRI 协变量回归。

该脚本只负责回归协变量，不做去趋势和带通滤波。
协变量可以按开关选择是否包含：
- Global Signal
- White Matter Signal
- CSF Signal
- Head Motion
"""

import argparse
import json
import warnings
from pathlib import Path

import nibabel as nib
import numpy as np
from nilearn import signal
from nilearn.masking import apply_mask, unmask

from fmri_utils import (
    build_motion_confounds,
    build_signal_confounds,
    load_mask,
    load_motion,
    zscore_cols,
)


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--func", required=True)
    parser.add_argument("--motion", required=True)
    parser.add_argument("--brain-mask", required=True)
    parser.add_argument("--wm-mask", default="")
    parser.add_argument("--csf-mask", default="")
    parser.add_argument("--gs-mask", default="")
    parser.add_argument("--regress-gs", type=int, default=0)
    parser.add_argument("--regress-wm", type=int, default=1)
    parser.add_argument("--regress-csf", type=int, default=1)
    parser.add_argument("--regress-hm", type=int, default=1)
    parser.add_argument("--hm-model", type=int, default=24)
    parser.add_argument("--output-func", required=True)
    parser.add_argument("--output-qc", required=True)
    return parser.parse_args()


def masked_mean_signal(img, mask):
    """在指定掩膜内提取平均时序。"""
    if mask is None or np.count_nonzero(mask) == 0:
        return None
    mask_img = nib.Nifti1Image(mask.astype(np.uint8), img.affine, img.header)
    return apply_mask(img, mask_img).mean(axis=1)


def build_confounds(args, func_img):
    """按配置构建协变量矩阵。"""
    n_tp = func_img.shape[3]
    parts = []
    qc = {
        "regress_gs": bool(args.regress_gs),
        "regress_wm": bool(args.regress_wm),
        "regress_csf": bool(args.regress_csf),
        "regress_hm": bool(args.regress_hm),
        "hm_model": int(args.hm_model),
        "n_motion_cols": 0,
        "n_gs_cols": 0,
        "n_wm_cols": 0,
        "n_csf_cols": 0,
    }

    if args.regress_hm:
        motion = load_motion(args.motion, n_tp)
        motion_block = build_motion_confounds(motion, args.hm_model)
        parts.append(motion_block)
        qc["n_motion_cols"] = int(motion_block.shape[1])

    wm_mask = load_mask(args.wm_mask, func_img.shape[:3])
    csf_mask = load_mask(args.csf_mask, func_img.shape[:3])
    gs_mask = load_mask(args.gs_mask, func_img.shape[:3])

    if args.regress_wm:
        wm_signal = masked_mean_signal(func_img, wm_mask)
        if wm_signal is None:
            raise ValueError("WM regression is enabled, but WM mask is empty or missing")
        wm_block = build_signal_confounds(wm_signal)
        parts.append(wm_block)
        qc["n_wm_cols"] = int(wm_block.shape[1])

    if args.regress_csf:
        csf_signal = masked_mean_signal(func_img, csf_mask)
        if csf_signal is None:
            raise ValueError("CSF regression is enabled, but CSF mask is empty or missing")
        csf_block = build_signal_confounds(csf_signal)
        parts.append(csf_block)
        qc["n_csf_cols"] = int(csf_block.shape[1])

    if args.regress_gs:
        gs_signal = masked_mean_signal(func_img, gs_mask)
        if gs_signal is None:
            raise ValueError("GS regression is enabled, but GS mask is empty or missing")
        gs_block = build_signal_confounds(gs_signal)
        parts.append(gs_block)
        qc["n_gs_cols"] = int(gs_block.shape[1])

    if not parts:
        return np.zeros((n_tp, 0), dtype=float), qc

    return np.column_stack(parts), qc


def main():
    """执行协变量回归并写出结果。"""
    args = parse_args()
    func_img = nib.load(args.func)
    if len(func_img.shape) != 4:
        raise ValueError("Regress-out-covariates expects 4D fMRI input")

    brain_mask = load_mask(args.brain_mask, func_img.shape[:3])
    if brain_mask is None:
        raise ValueError("Brain mask is required for regress-out-covariates")
    mask_img = nib.Nifti1Image(brain_mask.astype(np.uint8), func_img.affine, func_img.header)

    confounds, qc = build_confounds(args, func_img)
    masked_data = apply_mask(func_img, mask_img)
    clean_confounds = None
    if confounds.size > 0:
        # 这里显式对 confounds 做列标准化，避免把预处理细节交给 nilearn 的未来默认值。
        clean_confounds = zscore_cols(confounds)

    with warnings.catch_warnings():
        # confounds 已在上面显式标准化；这些 warning 对当前流程不再适用。
        warnings.filterwarnings(
            "ignore",
            message="When confounds are provided, one must perform detrend and/or standardize confounds.*",
            category=UserWarning,
        )
        warnings.filterwarnings(
            "ignore",
            message="From release 0.14.0, confounds will be standardized using the sample std instead of the population std.*",
            category=DeprecationWarning,
        )
        cleaned = signal.clean(
            masked_data,
            confounds=clean_confounds,
            detrend=False,
            standardize=None,
            standardize_confounds=False,
            ensure_finite=True,
        )

    out_img = unmask(cleaned, mask_img)
    out_img.set_data_dtype(np.float32)
    nib.save(out_img, args.output_func)

    qc.update(
        {
            "backend": "nilearn.signal.clean",
            "n_timepoints": int(func_img.shape[3]),
            "n_confound_cols": int(confounds.shape[1]),
            "confounds_standardized_explicitly": bool(confounds.size > 0),
        }
    )
    Path(args.output_qc).write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
