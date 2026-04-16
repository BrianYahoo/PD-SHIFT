#!/usr/bin/env python3
"""执行 fMRI 时间去趋势。"""

import argparse
import json
import sys
from pathlib import Path

import nibabel as nib
import numpy as np
from nilearn import signal
from nilearn.masking import apply_mask, unmask

UTILS_ROOT = Path(__file__).resolve().parents[2]
if str(UTILS_ROOT) not in sys.path:
    sys.path.insert(0, str(UTILS_ROOT))

from phase2_fmri.shared.fmri_utils import load_mask


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--func", required=True)
    parser.add_argument("--brain-mask", required=True)
    parser.add_argument("--detrend-order", type=int, default=1)
    parser.add_argument("--output-func", required=True)
    parser.add_argument("--output-qc", required=True)
    return parser.parse_args()


def main():
    """执行时间去趋势并写出结果。"""
    args = parse_args()
    func_img = nib.load(args.func)
    if len(func_img.shape) != 4:
        raise ValueError("Temporal detrend expects 4D fMRI input")

    brain_mask = load_mask(args.brain_mask, func_img.shape[:3])
    if brain_mask is None:
        raise ValueError("Brain mask is required for temporal detrend")
    mask_img = nib.Nifti1Image(brain_mask.astype(np.uint8), func_img.affine, func_img.header)

    masked_data = apply_mask(func_img, mask_img)
    cleaned = signal.clean(
        masked_data,
        confounds=None,
        detrend=bool(args.detrend_order >= 1),
        standardize=None,
        ensure_finite=True,
    )

    out_img = unmask(cleaned, mask_img)
    out_img.set_data_dtype(np.float32)
    nib.save(out_img, args.output_func)

    qc = {
        "backend": "nilearn.signal.clean",
        "detrend_order": int(args.detrend_order),
        "n_timepoints": int(func_img.shape[3]),
    }
    Path(args.output_qc).write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
