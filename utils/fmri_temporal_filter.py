#!/usr/bin/env python3
"""执行 fMRI 时间带通滤波。"""

import argparse
import json
from pathlib import Path

import nibabel as nib
import numpy as np
from nilearn import signal
from nilearn.masking import apply_mask, unmask

from fmri_utils import load_mask


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--func", required=True)
    parser.add_argument("--brain-mask", required=True)
    parser.add_argument("--tr", type=float, required=True)
    parser.add_argument("--low-cut", type=float, default=0.01)
    parser.add_argument("--high-cut", type=float, default=0.10)
    parser.add_argument("--output-func", required=True)
    parser.add_argument("--output-qc", required=True)
    return parser.parse_args()


def main():
    """执行带通滤波并写出结果。"""
    args = parse_args()
    func_img = nib.load(args.func)
    if len(func_img.shape) != 4:
        raise ValueError("Temporal filter expects 4D fMRI input")

    brain_mask = load_mask(args.brain_mask, func_img.shape[:3])
    if brain_mask is None:
        raise ValueError("Brain mask is required for temporal filter")
    mask_img = nib.Nifti1Image(brain_mask.astype(np.uint8), func_img.affine, func_img.header)

    masked_data = apply_mask(func_img, mask_img)
    cleaned = signal.clean(
        masked_data,
        confounds=None,
        detrend=False,
        standardize=None,
        low_pass=float(args.high_cut),
        high_pass=float(args.low_cut),
        t_r=float(args.tr),
        ensure_finite=True,
    )

    out_img = unmask(cleaned, mask_img)
    out_img.set_data_dtype(np.float32)
    nib.save(out_img, args.output_func)

    qc = {
        "backend": "nilearn.signal.clean",
        "tr": float(args.tr),
        "low_cut": float(args.low_cut),
        "high_cut": float(args.high_cut),
        "n_timepoints": int(func_img.shape[3]),
    }
    Path(args.output_qc).write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
