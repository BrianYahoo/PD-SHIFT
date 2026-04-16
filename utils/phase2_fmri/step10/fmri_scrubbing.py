#!/usr/bin/env python3
"""根据运动参数计算 FD，并输出 toxic frame 标记。

该脚本不仅输出数值版 FD 和 scrub mask，
还会生成 4D toxic frame 可视化 NIfTI，便于快速检查。
"""

import argparse
import json
import sys
import tempfile
from pathlib import Path

import nibabel as nib
import numpy as np

UTILS_ROOT = Path(__file__).resolve().parents[2]
if str(UTILS_ROOT) not in sys.path:
    sys.path.insert(0, str(UTILS_ROOT))

from phase2_fmri.shared.fmri_utils import load_motion, power_fd


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--func", required=True)
    parser.add_argument("--motion", required=True)
    parser.add_argument("--brain-mask", default="")
    parser.add_argument("--enabled", type=int, default=1)
    parser.add_argument("--fd-threshold", type=float, required=True)
    parser.add_argument("--scrub-before", type=int, default=0)
    parser.add_argument("--scrub-after", type=int, default=0)
    parser.add_argument("--output-fd", required=True)
    parser.add_argument("--output-toxic-mask", required=True)
    parser.add_argument("--output-toxic-nifti", required=True)
    parser.add_argument("--output-qc", required=True)
    return parser.parse_args()


def build_toxic_mask(fd, threshold, before, after):
    """按照阈值以及前后扩展规则生成 toxic frame mask。"""
    toxic = np.zeros(fd.shape[0], dtype=bool)
    base = np.where(fd > threshold)[0]
    toxic[base] = True
    for step in range(1, before + 1):
        idx = base - step
        idx = idx[idx >= 0]
        toxic[idx] = True
    for step in range(1, after + 1):
        idx = base + step
        idx = idx[idx < fd.shape[0]]
        toxic[idx] = True
    return toxic


def main():
    """执行 scrubbing 标记并输出 FD / mask / QC。"""
    args = parse_args()
    func_img = nib.load(args.func)
    if len(func_img.shape) != 4:
        raise ValueError("Scrubbing expects 4D fMRI input")

    motion = load_motion(args.motion, func_img.shape[3])
    fd = power_fd(motion)
    suggested_toxic = build_toxic_mask(fd, args.fd_threshold, args.scrub_before, args.scrub_after)
    # 默认可以关闭 scrubbing；关闭时仍保留 FD 统计，但不真正标记毒瘤帧。
    if args.enabled:
        toxic = suggested_toxic
    else:
        toxic = np.zeros_like(suggested_toxic, dtype=bool)
    np.savetxt(args.output_fd, fd, fmt="%.8f")
    np.savetxt(args.output_toxic_mask, toxic.astype(int), fmt="%d")

    if args.brain_mask:
        brain_mask = np.asarray(nib.load(args.brain_mask).dataobj, dtype=np.float32) > 0.5
    else:
        brain_mask = np.abs(np.asarray(func_img.dataobj[:, :, :, 0], dtype=np.float32)) > 0
    # 生成一个 4D NIfTI，把 toxic frame 在时间轴上可视化出来。
    with tempfile.NamedTemporaryFile(suffix=".dat", delete=False) as tmp:
        toxic_img = np.memmap(tmp.name, dtype=np.uint8, mode="w+", shape=func_img.shape)
        for z_idx in range(func_img.shape[2]):
            toxic_img[:, :, z_idx, :] = brain_mask[:, :, z_idx][:, :, None].astype(np.uint8) * toxic.astype(np.uint8)[None, None, :]
        out_img = nib.Nifti1Image(toxic_img, func_img.affine, func_img.header)
        out_img.set_data_dtype(np.uint8)
        nib.save(out_img, args.output_toxic_nifti)
    Path(tmp.name).unlink(missing_ok=True)

    qc = {
        "enabled": bool(args.enabled),
        "fd_threshold": float(args.fd_threshold),
        "n_timepoints": int(fd.shape[0]),
        "fd_mean": float(np.mean(fd)),
        "fd_max": float(np.max(fd)),
        "toxic_count": int(np.count_nonzero(toxic)),
        "toxic_indices": [int(i) for i in np.where(toxic)[0].tolist()],
        "suggested_toxic_count": int(np.count_nonzero(suggested_toxic)),
        "suggested_toxic_indices": [int(i) for i in np.where(suggested_toxic)[0].tolist()],
    }
    Path(args.output_qc).write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
