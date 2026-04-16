#!/usr/bin/env python3
"""构建 20 个皮层下脑区的体素 atlas。

该脚本把 aparc+aseg 中的常规皮层下结构、DISTAL 中的 GPe/GPi/STN，
以及黑质标签合并成统一的 20 ROI 图谱，并输出对应标签表。
"""

import argparse
import csv
from pathlib import Path

import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to


SUBCORTICAL_SPEC = [
    (1, "L.CER", "aparc", [7, 8]),
    (2, "L.TH", "aparc", [10]),
    (3, "L.CA", "aparc", [11]),
    (4, "L.PU", "aparc", [12]),
    (5, "L.HI", "aparc", [17]),
    (6, "L.AC", "aparc", [26]),
    (7, "lh-GPe", "distal", "lh_GPe"),
    (8, "lh-GPi", "distal", "lh_GPi"),
    (9, "lh-STN", "distal", "lh_STN"),
    (10, "SubstantiaNigraLH", "sn", "lh_SN"),
    (11, "R.CER", "aparc", [46, 47]),
    (12, "R.TH", "aparc", [49]),
    (13, "R.CA", "aparc", [50]),
    (14, "R.PU", "aparc", [51]),
    (15, "R.HI", "aparc", [53]),
    (16, "R.AC", "aparc", [58]),
    (17, "rh-GPe", "distal", "rh_GPe"),
    (18, "rh-GPi", "distal", "rh_GPi"),
    (19, "rh-STN", "distal", "rh_STN"),
    (20, "SubstantiaNigraRH", "sn", "rh_SN"),
]


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--aparc", required=True)
    parser.add_argument("--distal", required=True)
    parser.add_argument("--distal-label-tsv", required=True)
    parser.add_argument("--sn", required=True)
    parser.add_argument("--sn-label-tsv", required=True)
    parser.add_argument("--output-nii", required=True)
    parser.add_argument("--output-tsv", required=True)
    return parser.parse_args()


def load_label_map(path: Path):
    """把标签 TSV 读成 name -> index 的字典。"""
    out = {}
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            out[row["name"].strip()] = int(row["index"])
    return out


def load_aligned_labels(path: str, reference_img: nib.spatialimages.SpatialImage):
    """读取标签图，并在必要时重采样到参考空间。"""
    img = nib.load(path)
    if img.shape != reference_img.shape or not np.allclose(img.affine, reference_img.affine):
        img = resample_from_to(img, reference_img, order=0)
    return np.asarray(img.dataobj, dtype=np.int32)


def main():
    """按照预定义 ROI 规则生成最终皮层下 atlas。"""
    args = parse_args()
    aparc_img = nib.load(args.aparc)
    aparc = np.asarray(aparc_img.dataobj, dtype=np.int32)
    distal = load_aligned_labels(args.distal, aparc_img)
    sn = load_aligned_labels(args.sn, aparc_img)

    distal_map = load_label_map(Path(args.distal_label_tsv))
    sn_map = load_label_map(Path(args.sn_label_tsv))

    out = np.zeros(aparc.shape, dtype=np.int16)
    rows = []
    # 逐个 ROI 生成 mask，并统一写入新的 1..20 标签编号。
    for idx, name, source, spec in SUBCORTICAL_SPEC:
        if source == "aparc":
            mask = np.isin(aparc, spec)
            source_desc = ",".join(str(x) for x in spec)
        elif source == "distal":
            mask = distal == distal_map[spec]
            source_desc = spec
        else:
            mask = sn == sn_map[spec]
            source_desc = spec

        out[mask] = idx
        rows.append(
            {
                "index": idx,
                "name": name,
                "source": source,
                "source_definition": source_desc,
                "voxel_count": int(np.count_nonzero(mask)),
            }
        )

    out_img = nib.Nifti1Image(out, aparc_img.affine, aparc_img.header)
    out_img.set_data_dtype(np.int16)
    nib.save(out_img, args.output_nii)

    with Path(args.output_tsv).open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["index", "name", "source", "source_definition", "voxel_count"],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
