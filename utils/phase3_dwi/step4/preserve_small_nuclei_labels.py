#!/usr/bin/env python3
"""在 DWI 空间补回缺失的小核团标签。

策略很保守：
1. 只处理 protected labels。
2. 只在标签在源 atlas 中存在、但在目标 atlas 中缺失时介入。
3. 使用 label 二值图经 trilinear 投影后的概率图，按体积比例挑选目标体素。
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from pathlib import Path

import nibabel as nib
import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-atlas", required=True)
    parser.add_argument("--target-atlas", required=True)
    parser.add_argument("--transform-mat", required=True)
    parser.add_argument("--labels-tsv", required=True)
    parser.add_argument("--candidate-dir", required=True)
    parser.add_argument("--protected-labels", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--img2imgcoord-bin", default="img2imgcoord")
    return parser.parse_args()


def voxel_volume(img: nib.spatialimages.SpatialImage) -> float:
    return float(abs(np.linalg.det(img.affine[:3, :3])))


def load_label_names(path: Path) -> dict[int, str]:
    mapping: dict[int, str] = {}
    with path.open("r", encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            mapping[int(row["index"])] = row["label"]
    return mapping


def place_centroid_seed(
    repaired: np.ndarray,
    source_data: np.ndarray,
    label_idx: int,
    source_atlas: str,
    target_atlas: str,
    transform_mat: str,
    img2imgcoord_bin: str,
    protected_set: set[int],
) -> tuple[int, int, int] | None:
    coords = np.argwhere(source_data == label_idx)
    if coords.size == 0:
        return None
    centroid = coords.mean(axis=0)
    proc = subprocess.run(
        [
            img2imgcoord_bin,
            "-src",
            source_atlas,
            "-dest",
            target_atlas,
            "-xfm",
            transform_mat,
            "-vox",
            "-",
        ],
        input=f"{centroid[0]} {centroid[1]} {centroid[2]}\n",
        text=True,
        capture_output=True,
        check=True,
    )
    dest_line = proc.stdout.strip().splitlines()[-1]
    dest_xyz = [int(round(float(v))) for v in dest_line.split()[:3]]
    shape = repaired.shape
    dest_xyz = [
        max(0, min(dest_xyz[0], shape[0] - 1)),
        max(0, min(dest_xyz[1], shape[1] - 1)),
        max(0, min(dest_xyz[2], shape[2] - 1)),
    ]

    offsets = [(0, 0, 0)]
    for radius in (1, 2):
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                for dz in range(-radius, radius + 1):
                    offsets.append((dx, dy, dz))

    for dx, dy, dz in offsets:
        x = max(0, min(dest_xyz[0] + dx, shape[0] - 1))
        y = max(0, min(dest_xyz[1] + dy, shape[1] - 1))
        z = max(0, min(dest_xyz[2] + dz, shape[2] - 1))
        if int(repaired[x, y, z]) not in protected_set:
            repaired[x, y, z] = label_idx
            return (x, y, z)
    return None


def main() -> None:
    args = parse_args()
    src_img = nib.load(args.source_atlas)
    tgt_img = nib.load(args.target_atlas)
    src = np.asarray(src_img.dataobj, dtype=np.int16)
    tgt = np.asarray(tgt_img.dataobj, dtype=np.int16)
    repaired = tgt.copy()

    src_voxvol = voxel_volume(src_img)
    tgt_voxvol = voxel_volume(tgt_img)
    protected = [int(v.strip()) for v in args.protected_labels.split(",") if v.strip()]
    protected_set = set(protected)
    label_names = load_label_names(Path(args.labels_tsv))
    report: list[dict[str, object]] = []

    for label_idx in protected:
        src_count = int(np.count_nonzero(src == label_idx))
        tgt_count = int(np.count_nonzero(repaired == label_idx))
        expected_count = max(1, int(round(src_count * src_voxvol / tgt_voxvol))) if src_count > 0 else 0
        candidate_path = Path(args.candidate_dir) / f"label_{label_idx}_prob.nii.gz"

        item: dict[str, object] = {
            "index": label_idx,
            "label": label_names.get(label_idx, str(label_idx)),
            "source_voxels": src_count,
            "target_voxels_before": tgt_count,
            "expected_target_voxels": expected_count,
            "candidate_map": str(candidate_path),
            "action": "keep",
        }

        if src_count == 0:
            item["action"] = "skip_source_missing"
            report.append(item)
            continue
        if tgt_count > 0:
            item["action"] = "skip_already_present"
            report.append(item)
            continue
        if not candidate_path.exists():
            item["action"] = "skip_candidate_missing"
            report.append(item)
            continue

        candidate = np.asarray(nib.load(candidate_path).dataobj, dtype=np.float32)
        allowed = candidate > 0
        allowed &= (~np.isin(repaired, list(protected_set))) | (repaired == label_idx)
        flat_idx = np.flatnonzero(allowed)

        if flat_idx.size == 0:
            seeded = place_centroid_seed(
                repaired,
                src,
                label_idx,
                args.source_atlas,
                args.target_atlas,
                args.transform_mat,
                args.img2imgcoord_bin,
                protected_set,
            )
            if seeded is None:
                item["action"] = "skip_candidate_empty"
            else:
                item["action"] = "seeded_centroid"
                item["seed_voxel"] = [int(v) for v in seeded]
                item["target_voxels_after"] = int(np.count_nonzero(repaired == label_idx))
            report.append(item)
            continue

        scores = candidate.flat[flat_idx]
        if np.allclose(scores, scores[0]):
            chosen = flat_idx
            item["selection_mode"] = "all_candidate_voxels"
        else:
            order = flat_idx[np.argsort(scores)[::-1]]
            keep_n = min(expected_count, order.size)
            chosen = order[:keep_n]
            item["selection_mode"] = "top_probability"
        repaired.flat[chosen] = label_idx
        item["action"] = "repaired"
        item["target_voxels_after"] = int(np.count_nonzero(repaired == label_idx))
        report.append(item)

    out_img = nib.Nifti1Image(repaired.astype(np.int16), tgt_img.affine, tgt_img.header)
    out_img.set_data_dtype(np.int16)
    nib.save(out_img, args.output)
    Path(args.report).write_text(json.dumps({"protected_labels": protected, "items": report}, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
