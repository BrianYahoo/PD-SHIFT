#!/usr/bin/env python3
"""只对零连接保护核团做 connectome-only fallback 修补。"""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import nibabel as nib
import numpy as np
from scipy.ndimage import binary_dilation


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tracks", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--matrix", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--weight-mode", choices=("sift2", "count"), required=True)
    parser.add_argument("--scale-mode", choices=("raw", "invnodevol"), required=True)
    parser.add_argument("--sift2-weights", required=True)
    parser.add_argument("--radial-search", required=True, type=float)
    parser.add_argument("--protected-labels", required=True)
    parser.add_argument("--max-dilation", type=int, default=12)
    parser.add_argument("--nthreads", type=int, default=1)
    return parser.parse_args()


def zero_labels(matrix: np.ndarray, protected: list[int]) -> list[int]:
    result: list[int] = []
    for idx in protected:
        row_sum = float(matrix[idx - 1].sum())
        col_sum = float(matrix[:, idx - 1].sum())
        if row_sum == 0.0 and col_sum == 0.0:
            result.append(idx)
    return result


def build_dilated_atlas(orig: np.ndarray, unresolved: list[int], protected: list[int], iterations: int) -> np.ndarray:
    data = orig.copy()
    occupied = np.isin(orig, protected)
    for idx in unresolved:
        mask = orig == idx
        grown = binary_dilation(mask, iterations=iterations)
        add = grown & ~occupied
        data[add] = idx
        occupied |= data == idx
    # unresolved 外的保护标签不参与扩张，避免对其他小核团造成额外偏移。
    return data.astype(np.int16)


def run_connectome(
    args: argparse.Namespace,
    atlas_path: Path,
    out_path: Path,
) -> None:
    cmd = [
        "tck2connectome",
        args.tracks,
        str(atlas_path),
        str(out_path),
        "-symmetric",
        "-zero_diagonal",
        "-assignment_radial_search",
        str(args.radial_search),
        "-nthreads",
        str(args.nthreads),
    ]
    if args.weight_mode == "sift2":
        cmd.extend(["-tck_weights_in", args.sift2_weights])
    if args.scale_mode == "invnodevol":
        cmd.append("-scale_invnodevol")
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main() -> None:
    args = parse_args()
    protected = [int(v.strip()) for v in args.protected_labels.split(",") if v.strip()]
    matrix = np.loadtxt(args.matrix, delimiter=",")
    repaired = matrix.copy()
    initial_zero = zero_labels(repaired, protected)
    report: dict[str, object] = {
        "protected_labels": protected,
        "initial_zero_labels": initial_zero,
        "max_dilation": args.max_dilation,
        "rescued": {},
        "unresolved_final": [],
    }

    if not initial_zero:
        np.savetxt(args.output, repaired, delimiter=",", fmt="%.10g")
        Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")
        return

    atlas_img = nib.load(args.atlas)
    atlas_data = np.asarray(atlas_img.dataobj, dtype=np.int16)
    unresolved = list(initial_zero)

    with tempfile.TemporaryDirectory(prefix="cns_zero_label_repair_") as tmpdir:
        tmpdir_path = Path(tmpdir)
        for dilation in range(1, args.max_dilation + 1):
            if not unresolved:
                break
            dilated = build_dilated_atlas(atlas_data, unresolved, protected, dilation)
            atlas_path = tmpdir_path / f"atlas_dil{dilation}.nii.gz"
            matrix_path = tmpdir_path / f"matrix_dil{dilation}.csv"
            nib.save(nib.Nifti1Image(dilated, atlas_img.affine, atlas_img.header), atlas_path)
            run_connectome(args, atlas_path, matrix_path)
            candidate = np.loadtxt(matrix_path, delimiter=",")

            still_zero: list[int] = []
            for idx in unresolved:
                if float(candidate[idx - 1].sum()) > 0.0 or float(candidate[:, idx - 1].sum()) > 0.0:
                    repaired[idx - 1, :] = candidate[idx - 1, :]
                    repaired[:, idx - 1] = candidate[:, idx - 1]
                    report["rescued"][str(idx)] = {"dilation": dilation}
                else:
                    still_zero.append(idx)
            unresolved = still_zero

    report["unresolved_final"] = unresolved
    np.savetxt(args.output, repaired, delimiter=",", fmt="%.10g")
    Path(args.report).write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
