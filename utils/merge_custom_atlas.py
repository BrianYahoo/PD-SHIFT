#!/usr/bin/env python3
"""把 Desikan 皮层与自定义皮层下 atlas 融合为 88 ROI 图谱。

最终输出顺序严格服从 framework/details/roi.tsv。
"""

import argparse
import csv
from pathlib import Path

import nibabel as nib
import numpy as np


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

DESIKAN_TO_TVP = {
    "lh_bankssts": "L.BSTS",
    "lh_caudalanteriorcingulate": "L.CACG",
    "lh_caudalmiddlefrontal": "L.CMFG",
    "lh_cuneus": "L.CU",
    "lh_entorhinal": "L.EC",
    "lh_fusiform": "L.FG",
    "lh_inferiorparietal": "L.IPG",
    "lh_inferiortemporal": "L.ITG",
    "lh_isthmuscingulate": "L.ICG",
    "lh_lateraloccipital": "L.LOG",
    "lh_lateralorbitofrontal": "L.LOFG",
    "lh_lingual": "L.LG",
    "lh_medialorbitofrontal": "L.MOFG",
    "lh_middletemporal": "L.MTG",
    "lh_parahippocampal": "L.PHIG",
    "lh_paracentral": "L.PaCG",
    "lh_parsopercularis": "L.POP",
    "lh_parsorbitalis": "L.POR",
    "lh_parstriangularis": "L.PTR",
    "lh_pericalcarine": "L.PCAL",
    "lh_postcentral": "L.PoCG",
    "lh_posteriorcingulate": "L.PCG",
    "lh_precentral": "L.PrCG",
    "lh_precuneus": "L.PCU",
    "lh_rostralanteriorcingulate": "L.RACG",
    "lh_rostralmiddlefrontal": "L.RMFG",
    "lh_superiorfrontal": "L.SFG",
    "lh_superiorparietal": "L.SPG",
    "lh_superiortemporal": "L.STG",
    "lh_supramarginal": "L.SMG",
    "lh_frontalpole": "L.FP",
    "lh_temporalpole": "L.TP",
    "lh_transversetemporal": "L.TTG",
    "lh_insula": "L.IN",
    "rh_bankssts": "R.BSTS",
    "rh_caudalanteriorcingulate": "R.CACG",
    "rh_caudalmiddlefrontal": "R.CMFG",
    "rh_cuneus": "R.CU",
    "rh_entorhinal": "R.EC",
    "rh_fusiform": "R.FG",
    "rh_inferiorparietal": "R.IPG",
    "rh_inferiortemporal": "R.ITG",
    "rh_isthmuscingulate": "R.ICG",
    "rh_lateraloccipital": "R.LOG",
    "rh_lateralorbitofrontal": "R.LOFG",
    "rh_lingual": "R.LG",
    "rh_medialorbitofrontal": "R.MOFG",
    "rh_middletemporal": "R.MTG",
    "rh_parahippocampal": "R.PHIG",
    "rh_paracentral": "R.PaCG",
    "rh_parsopercularis": "R.POP",
    "rh_parsorbitalis": "R.POR",
    "rh_parstriangularis": "R.PTR",
    "rh_pericalcarine": "R.PCAL",
    "rh_postcentral": "R.PoCG",
    "rh_posteriorcingulate": "R.PCG",
    "rh_precentral": "R.PrCG",
    "rh_precuneus": "R.PCU",
    "rh_rostralanteriorcingulate": "R.RACG",
    "rh_rostralmiddlefrontal": "R.RMFG",
    "rh_superiorfrontal": "R.SFG",
    "rh_superiorparietal": "R.SPG",
    "rh_superiortemporal": "R.STG",
    "rh_supramarginal": "R.SMG",
    "rh_frontalpole": "R.FP",
    "rh_temporalpole": "R.TP",
    "rh_transversetemporal": "R.TTG",
    "rh_insula": "R.IN",
}


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--aparc", required=True)
    parser.add_argument("--subcortical", required=True)
    parser.add_argument("--subcortical-label-tsv", required=True)
    parser.add_argument("--roi-master-tsv", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--output-labels", required=True)
    return parser.parse_args()


def load_roi_master(path: Path):
    """读取 88 ROI 主表，并建立 TVP 标签到行信息的映射。"""
    rows = []
    by_tvp = {}
    with path.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            row["index"] = int(row["index"])
            rows.append(row)
            by_tvp[row["label (TVP)"].strip()] = row
    rows.sort(key=lambda x: x["index"])
    return rows, by_tvp


def main():
    """按 roi.tsv 的固定顺序合并皮层与皮层下标签。"""
    args = parse_args()
    aparc_img = nib.load(args.aparc)
    subc_img = nib.load(args.subcortical)
    aparc = np.asarray(aparc_img.dataobj, dtype=np.int32)
    subc = np.asarray(subc_img.dataobj, dtype=np.int32)
    roi_master_rows, roi_master_by_tvp = load_roi_master(Path(args.roi_master_tsv))

    out = np.zeros(aparc.shape, dtype=np.int16)
    rows = []

    # 先按 roi.tsv 定义的 index 写入 68 个皮层 ROI。
    for fs_idx, fs_name in DESIKAN_68:
        tvp_label = DESIKAN_TO_TVP[fs_name]
        master = roi_master_by_tvp[tvp_label]
        out_idx = int(master["index"])
        mask = aparc == fs_idx
        out[mask] = out_idx
        rows.append(
            {
                "index": out_idx,
                "label (TVP)": master["label (TVP)"],
                "label": master["label"],
                "abbreviation": master["abbreviation"],
                "english_full_name": master["english_full_name"],
                "chinese_full_name": master["chinese_full_name"],
                "source": "Desikan",
                "original_label": fs_idx,
                "voxel_count": int(np.count_nonzero(mask)),
            }
        )

    # 再按 roi.tsv 主表顺序写入 20 个皮层下 ROI。
    with Path(args.subcortical_label_tsv).open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            subc_idx = int(row["index"])
            tvp_label = row["name"].strip()
            master = roi_master_by_tvp[tvp_label]
            out_idx = int(master["index"])
            mask = subc == subc_idx
            out[mask] = out_idx
            rows.append(
                {
                    "index": out_idx,
                    "label (TVP)": master["label (TVP)"],
                    "label": master["label"],
                    "abbreviation": master["abbreviation"],
                    "english_full_name": master["english_full_name"],
                    "chinese_full_name": master["chinese_full_name"],
                    "source": "Subcortical",
                    "original_label": subc_idx,
                    "voxel_count": int(np.count_nonzero(mask)),
                }
            )

    # 对任何当前图谱中未占体素的 ROI，也保留零体素记录，保证 labels.tsv 始终完整 88 行。
    existing_idx = {int(row["index"]) for row in rows}
    for master in roi_master_rows:
        if int(master["index"]) in existing_idx:
            continue
        rows.append(
            {
                "index": int(master["index"]),
                "label (TVP)": master["label (TVP)"],
                "label": master["label"],
                "abbreviation": master["abbreviation"],
                "english_full_name": master["english_full_name"],
                "chinese_full_name": master["chinese_full_name"],
                "source": "Missing",
                "original_label": "",
                "voxel_count": 0,
            }
        )

    out_img = nib.Nifti1Image(out, aparc_img.affine, aparc_img.header)
    out_img.set_data_dtype(np.int16)
    nib.save(out_img, args.output)

    rows.sort(key=lambda x: int(x["index"]))
    with Path(args.output_labels).open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "index",
                "label (TVP)",
                "label",
                "abbreviation",
                "english_full_name",
                "chinese_full_name",
                "source",
                "original_label",
                "voxel_count",
            ],
            delimiter="\t",
        )
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
