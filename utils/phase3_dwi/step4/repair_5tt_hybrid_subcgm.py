#!/usr/bin/env python3
"""修补 5TT 中的 STN / GPi 通道归属。

`5ttgen freesurfer` 可能会把这些深部靶点仍视作白质。
该脚本读取 hybrid atlas 后，把 STN / GPi 强制写入 5TT 的皮层下灰质通道。
"""

import argparse
import csv
import json
from pathlib import Path

import nibabel as nib
import numpy as np


TARGET_LABELS = {
    "lh-gpi", "rh-gpi", "lh-stn", "rh-stn",
    "l.gpi", "r.gpi", "l.stn", "r.stn",
}


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--five-tt", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--labels", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--output-qc", required=True)
    return parser.parse_args()


def load_target_indices(path: Path):
    """从标签表里找出 STN / GPi 对应的 ROI index。"""
    indices = []
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            raw = (row.get("label") or row.get("name") or "").strip()
            if raw.lower() in TARGET_LABELS:
                indices.append(int(row["index"]))
    return sorted(set(indices))


def main():
    """执行 5TT 的 STN / GPi 通道修补，并输出 QC。"""
    args = parse_args()
    five_tt_img = nib.load(args.five_tt)
    atlas_img = nib.load(args.atlas)

    five_tt = np.asarray(five_tt_img.dataobj, dtype=np.float32)
    atlas = np.asarray(atlas_img.dataobj, dtype=np.int32)
    if five_tt.ndim != 4 or five_tt.shape[3] != 5:
        raise ValueError("5TT image must be 4D with 5 volumes")
    if atlas.shape != five_tt.shape[:3]:
        raise ValueError("Atlas and 5TT shape mismatch")

    target_indices = load_target_indices(Path(args.labels))
    if not target_indices:
        raise ValueError("No STN/GPi labels found for 5TT repair")

    target_mask = np.isin(atlas, target_indices)
    repaired = five_tt.copy()
    repaired[target_mask, :] = 0.0
    repaired[target_mask, 1] = 1.0

    out_img = nib.Nifti1Image(repaired, five_tt_img.affine, five_tt_img.header)
    out_img.set_data_dtype(np.float32)
    nib.save(out_img, args.output)

    qc = {
        "target_indices": [int(idx) for idx in target_indices],
        "target_voxel_count": int(np.count_nonzero(target_mask)),
        "operation": "force STN/GPi voxels to subcortical GM channel in 5TT",
        "subcortical_channel_index": 1,
        "white_matter_channel_index": 2,
    }
    Path(args.output_qc).write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")


if __name__ == "__main__":
    main()
