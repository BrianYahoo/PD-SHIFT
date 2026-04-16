#!/usr/bin/env python3
"""把多个二值 ROI mask 组装成单张整数标签图。

输入是某个 atlas 目录下的多个 ROI mask；
输出是统一编号的 NIfTI 标签图和对应标签表。
"""

import argparse
import csv
from pathlib import Path

import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas-dir", required=True)
    parser.add_argument("--roi-list", required=True)
    parser.add_argument("--output-nii", required=True)
    parser.add_argument("--output-tsv", required=True)
    parser.add_argument("--threshold", type=float, default=0.5)
    return parser.parse_args()


def read_roi_table(path: Path):
    """读取 ROI 清单，得到需要合并的 hemi / roi 列表。"""
    items = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            items.append((row["hemi"].strip(), row["roi"].strip()))
    return items


def main():
    """把多个 ROI mask 合并为一张标签图。"""
    args = parse_args()
    atlas_dir = Path(args.atlas_dir)
    roi_items = read_roi_table(Path(args.roi_list))

    ref_path = atlas_dir.parent.parent / "t1.nii"
    if not ref_path.exists():
      ref_path = atlas_dir / "gm_mask.nii.gz"
    ref_img = nib.load(str(ref_path))
    labels = np.zeros(ref_img.shape, dtype=np.int16)
    rows = []

    # 按 roi-list 的顺序逐个装配标签，先到先占位。
    for idx, (hemi, roi) in enumerate(roi_items, start=1):
        roi_path = atlas_dir / hemi / f"{roi}.nii.gz"
        if not roi_path.exists():
            raise FileNotFoundError(roi_path)

        roi_img = nib.load(str(roi_path))
        if roi_img.shape != ref_img.shape or not np.allclose(roi_img.affine, ref_img.affine):
            roi_img = resample_from_to(roi_img, ref_img, order=0)

        data = np.asarray(roi_img.dataobj, dtype=np.float32)
        mask = data > args.threshold

        x_axis = float(ref_img.affine[0, 0]) * np.arange(labels.shape[0], dtype=np.float64) + float(ref_img.affine[0, 3])
        if hemi == "lh":
            mask = mask & (x_axis < 0)[:, None, None]
        elif hemi == "rh":
            mask = mask & (x_axis > 0)[:, None, None]

        assign_mask = mask & (labels == 0)
        overlap = int(np.count_nonzero(mask & (labels > 0)))
        labels[assign_mask] = idx
        rows.append(
            {
                "index": idx,
                "name": f"{hemi}_{roi}",
                "hemi": hemi,
                "roi": roi,
                "voxel_count": int(np.count_nonzero(labels == idx)),
                "overlap_with_previous_voxels": overlap,
                "source_mask": str(roi_path),
            }
        )

    out_img = nib.Nifti1Image(labels, ref_img.affine, ref_img.header)
    out_img.set_data_dtype(np.int16)
    nib.save(out_img, args.output_nii)

    with Path(args.output_tsv).open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["index", "name", "hemi", "roi", "voxel_count", "overlap_with_previous_voxels", "source_mask"],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
