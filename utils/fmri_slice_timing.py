#!/usr/bin/env python3
"""基于 BIDS JSON 里的 SliceTiming 做 slice timing correction。"""

import argparse
import json
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy.interpolate import interp1d


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--json", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def detect_slice_axis(shape, n_slices):
    """根据 SliceTiming 长度推断切片所在维度。"""
    candidates = [axis for axis in range(3) if shape[axis] == n_slices]
    if not candidates:
        raise ValueError(f"Cannot match SliceTiming length {n_slices} to image shape {shape[:3]}")
    if 2 in candidates:
        return 2
    return candidates[0]


def main():
    """执行逐切片插值，得到校正后的 4D 图像。"""
    args = parse_args()
    meta = json.loads(Path(args.json).read_text(encoding="utf-8"))
    tr = float(meta["RepetitionTime"])
    slice_timing = np.asarray(meta.get("SliceTiming", []), dtype=float)
    if slice_timing.size == 0:
        raise ValueError("SliceTiming is missing")

    img = nib.load(args.input)
    data = np.asarray(img.dataobj, dtype=np.float32)
    if data.ndim != 4:
        raise ValueError("Slice timing correction expects 4D fMRI input")

    slice_axis = detect_slice_axis(data.shape, slice_timing.size)
    ref_time = float(np.median(slice_timing))
    n_tp = data.shape[3]
    base_times = np.arange(n_tp, dtype=float) * tr
    out = np.empty_like(data, dtype=np.float32)

    moved = np.moveaxis(data, slice_axis, 2)
    moved_out = np.moveaxis(out, slice_axis, 2)

    # 逐切片做时间插值，把每张 slice 对齐到统一参考时间。
    for slice_idx in range(moved.shape[2]):
        sampled_times = base_times + float(slice_timing[slice_idx])
        target_times = base_times + ref_time
        slab = moved[:, :, slice_idx, :].reshape((-1, n_tp))
        interp = interp1d(
            sampled_times,
            slab,
            axis=1,
            bounds_error=False,
            fill_value=(slab[:, 0], slab[:, -1]),
            assume_sorted=True,
        )
        corrected = interp(target_times).reshape(moved.shape[0], moved.shape[1], n_tp)
        moved_out[:, :, slice_idx, :] = corrected.astype(np.float32)

    out_img = nib.Nifti1Image(out, img.affine, img.header)
    out_img.set_data_dtype(np.float32)
    nib.save(out_img, args.output)


if __name__ == "__main__":
    main()
