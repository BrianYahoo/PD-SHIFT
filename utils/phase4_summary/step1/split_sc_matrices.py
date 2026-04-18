#!/usr/bin/env python3
"""Export typed SC matrices from the 88-node hybrid atlas connectome."""

import argparse
import csv
import json
from pathlib import Path

import numpy as np


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--labels-tsv", required=True)
    parser.add_argument("--count", required=True)
    parser.add_argument("--count-invnodevol", required=True)
    parser.add_argument("--sift2", required=True)
    parser.add_argument("--sift2-invnodevol", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--subject-id", required=True)
    return parser.parse_args()


def load_indices(labels_tsv: Path) -> tuple[list[int], list[int]]:
    cortical: list[int] = []
    subcortical: list[int] = []
    with labels_tsv.open("r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row_i, row in enumerate(reader):
            source = (row.get("source") or "").strip().lower()
            if source == "desikan":
                cortical.append(row_i)
            elif source == "subcortical":
                subcortical.append(row_i)
    if len(cortical) != 68 or len(subcortical) != 20:
        raise ValueError(
            f"Unexpected atlas split in {labels_tsv}: "
            f"cortical={len(cortical)}, subcortical={len(subcortical)}"
        )
    return cortical, subcortical


def save_matrix(path: Path, matrix: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savetxt(path, matrix, delimiter=",", fmt="%.10f")


def export_one(subject_id: str, sc_type: str, matrix_path: Path, out_dir: Path, cortical: list[int], subcortical: list[int]) -> dict:
    matrix = np.loadtxt(matrix_path, delimiter=",").astype(float)
    if matrix.shape != (88, 88):
        raise ValueError(f"Expected 88x88 SC matrix, got {matrix.shape}: {matrix_path}")

    exports = {
        "whole": (matrix, out_dir / "whole" / f"{subject_id}_DTI_connectome_{sc_type}.csv"),
        "cortex": (matrix[np.ix_(cortical, cortical)], out_dir / "cortex" / f"{subject_id}_DTI_connectome_{sc_type}_cortical.csv"),
        "subcortex": (matrix[np.ix_(subcortical, subcortical)], out_dir / "subcortex" / f"{subject_id}_DTI_connectome_{sc_type}_subcortical.csv"),
        "sub2cortex": (matrix[np.ix_(subcortical, cortical)], out_dir / "sub2cortex" / f"{subject_id}_DTI_connectome_{sc_type}_subcortex_cortex.csv"),
    }

    row = {"sc_type": sc_type, "source": str(matrix_path)}
    for scale, (arr, out_path) in exports.items():
        save_matrix(out_path, arr)
        row[f"{scale}_path"] = str(out_path)
        row[f"{scale}_shape"] = "x".join(str(v) for v in arr.shape)
    return row


def main():
    args = parse_args()
    labels_tsv = Path(args.labels_tsv)
    out_dir = Path(args.out_dir)
    subject_id = args.subject_id

    cortical, subcortical = load_indices(labels_tsv)
    rows = [
        export_one(subject_id, "count", Path(args.count), out_dir, cortical, subcortical),
        export_one(subject_id, "count_invnodevol", Path(args.count_invnodevol), out_dir, cortical, subcortical),
        export_one(subject_id, "sift2", Path(args.sift2), out_dir, cortical, subcortical),
        export_one(subject_id, "sift2_invnodevol", Path(args.sift2_invnodevol), out_dir, cortical, subcortical),
    ]

    manifest = out_dir / f"{subject_id}_DTI_connectome_typed_manifest.tsv"
    fields = [
        "sc_type",
        "source",
        "whole_path",
        "whole_shape",
        "cortex_path",
        "cortex_shape",
        "subcortex_path",
        "subcortex_shape",
        "sub2cortex_path",
        "sub2cortex_shape",
    ]
    with manifest.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, delimiter="\t", fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    qc = {
        "subject_id": subject_id,
        "n_cortical": len(cortical),
        "n_subcortical": len(subcortical),
        "sc_types": [row["sc_type"] for row in rows],
        "scales": ["whole", "cortex", "subcortex", "sub2cortex"],
        "manifest": str(manifest),
    }
    (out_dir / f"{subject_id}_DTI_connectome_typed_qc.json").write_text(
        json.dumps(qc, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
