#!/usr/bin/env python3
"""把 Desikan 皮层与 DISTAL 深部核团融合为最终 hybrid atlas。"""

import argparse
import csv
from pathlib import Path

import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to


LH_DESIKAN = [
    (1001, "lh_bankssts"),
    (1002, "lh_caudalanteriorcingulate"),
    (1003, "lh_caudalmiddlefrontal"),
    (1005, "lh_cuneus"),
    (1006, "lh_entorhinal"),
    (1007, "lh_fusiform"),
    (1008, "lh_inferiorparietal"),
    (1009, "lh_inferiortemporal"),
    (1010, "lh_isthmuscingulate"),
    (1011, "lh_lateraloccipital"),
    (1012, "lh_lateralorbitofrontal"),
    (1013, "lh_lingual"),
    (1014, "lh_medialorbitofrontal"),
    (1015, "lh_middletemporal"),
    (1016, "lh_parahippocampal"),
    (1017, "lh_paracentral"),
    (1018, "lh_parsopercularis"),
    (1019, "lh_parsorbitalis"),
    (1020, "lh_parstriangularis"),
    (1021, "lh_pericalcarine"),
    (1022, "lh_postcentral"),
    (1023, "lh_posteriorcingulate"),
    (1024, "lh_precentral"),
    (1025, "lh_precuneus"),
    (1026, "lh_rostralanteriorcingulate"),
    (1027, "lh_rostralmiddlefrontal"),
    (1028, "lh_superiorfrontal"),
    (1029, "lh_superiorparietal"),
    (1030, "lh_superiortemporal"),
    (1031, "lh_supramarginal"),
    (1032, "lh_frontalpole"),
    (1033, "lh_temporalpole"),
    (1034, "lh_transversetemporal"),
    (1035, "lh_insula"),
]
RH_DESIKAN = [(idx + 1000, name.replace("lh_", "rh_")) for idx, name in LH_DESIKAN]
DESIKAN_68 = LH_DESIKAN + RH_DESIKAN


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--aparc", required=True)
    parser.add_argument("--distal", required=True)
    parser.add_argument("--distal-label-tsv", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--output-labels", required=True)
    return parser.parse_args()


def normalize_distal_name(name: str):
    """把 DISTAL 标签名标准化到当前命名风格。"""
    return name.replace("_", "-")


def load_distal_labels(path: Path):
    """读取 DISTAL 标签表，并按 index 排序。"""
    items = []
    with path.open("r", encoding="utf-8") as f:
      reader = csv.DictReader(f, delimiter="\t")
      for row in reader:
          items.append((int(row["index"]), normalize_distal_name(row["name"].strip())))
    items.sort(key=lambda x: x[0])
    return items


def main():
    """生成最终 hybrid atlas 及标签表。"""
    args = parse_args()
    aparc_img = nib.load(args.aparc)
    distal_img = nib.load(args.distal)
    if distal_img.shape != aparc_img.shape or not np.allclose(distal_img.affine, aparc_img.affine):
        distal_img = resample_from_to(distal_img, aparc_img, order=0)

    aparc = np.asarray(aparc_img.dataobj, dtype=np.int32)
    distal = np.asarray(distal_img.dataobj, dtype=np.int32)
    distal_labels = load_distal_labels(Path(args.distal_label_tsv))

    out = np.zeros(aparc.shape, dtype=np.int16)
    rows = []

    # 先放入 68 个 Desikan 皮层 ROI。
    for new_idx, (fs_idx, name) in enumerate(DESIKAN_68, start=1):
        mask = aparc == fs_idx
        out[mask] = new_idx
        rows.append(
            {
                "index": new_idx,
                "name": name,
                "source": "Desikan",
                "original_label": fs_idx,
                "voxel_count": int(np.count_nonzero(mask)),
            }
        )

    # 再把 DISTAL 深部核团接到 69 之后。
    for offset, (distal_idx, distal_name) in enumerate(distal_labels, start=1):
        out_idx = 68 + offset
        mask = distal == distal_idx
        out[mask] = out_idx
        rows.append(
            {
                "index": out_idx,
                "name": distal_name,
                "source": "DISTAL",
                "original_label": distal_idx,
                "voxel_count": int(np.count_nonzero(mask)),
            }
        )

    out_img = nib.Nifti1Image(out, aparc_img.affine, aparc_img.header)
    out_img.set_data_dtype(np.int16)
    nib.save(out_img, args.output)

    rows.sort(key=lambda x: int(x["index"]))
    with Path(args.output_labels).open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["index", "name", "source", "original_label", "voxel_count"],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
