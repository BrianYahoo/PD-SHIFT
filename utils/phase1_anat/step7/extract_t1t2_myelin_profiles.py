#!/usr/bin/env python3
"""按 roi.tsv 顺序提取 88 ROI 的 T1w/T2w/Myelin 平均值。"""

import argparse
import csv
from pathlib import Path

import nibabel as nib
import numpy as np


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--t1", required=True)
    parser.add_argument("--t2", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--roi-tsv", required=True)
    parser.add_argument("--output-csv", required=True)
    parser.add_argument("--output-myelin", required=True)
    return parser.parse_args()


def load_roi_rows(path: Path):
    with path.open("r", encoding="utf-8") as f:
        rows = list(csv.DictReader(f, delimiter="\t"))
    for row in rows:
        row["index"] = int(row["index"])
    rows.sort(key=lambda row: row["index"])
    return rows


def safe_mean(values: np.ndarray) -> float:
    if values.size == 0:
        return float("nan")
    return float(np.mean(values))


def main():
    args = parse_args()

    t1_img = nib.load(args.t1)
    t2_img = nib.load(args.t2)
    atlas_img = nib.load(args.atlas)

    t1 = np.asarray(t1_img.dataobj, dtype=np.float32)
    t2 = np.asarray(t2_img.dataobj, dtype=np.float32)
    atlas = np.asarray(atlas_img.dataobj, dtype=np.int16)

    if t1.shape != t2.shape or t1.shape != atlas.shape:
        raise SystemExit("T1/T2/atlas shape mismatch")

    valid_ratio = np.isfinite(t1) & np.isfinite(t2) & (t2 > 1.0e-6)
    myelin = np.zeros(t1.shape, dtype=np.float32)
    myelin[valid_ratio] = t1[valid_ratio] / t2[valid_ratio]

    out_img = nib.Nifti1Image(myelin, t1_img.affine, t1_img.header)
    out_img.set_data_dtype(np.float32)
    nib.save(out_img, args.output_myelin)

    roi_rows = load_roi_rows(Path(args.roi_tsv))
    records = []
    for row in roi_rows:
        idx = int(row["index"])
        mask = atlas == idx
        region_valid = mask & valid_ratio
        records.append(
            {
                "index": idx,
                "label": row["label"],
                "t1w": safe_mean(t1[mask]),
                "t2w": safe_mean(t2[mask]),
                "myelin": safe_mean(myelin[region_valid]),
                "voxel_count": int(np.count_nonzero(mask)),
                "valid_myelin_voxel_count": int(np.count_nonzero(region_valid)),
            }
        )

    with Path(args.output_csv).open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "index",
                "label",
                "t1w",
                "t2w",
                "myelin",
                "voxel_count",
                "valid_myelin_voxel_count",
            ],
        )
        writer.writeheader()
        writer.writerows(records)


if __name__ == "__main__":
    main()
