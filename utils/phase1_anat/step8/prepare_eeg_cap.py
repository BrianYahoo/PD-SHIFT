#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
from pathlib import Path


STANDARD_10_10_64 = [
    "Cz",
    "Fp1", "Fpz", "Fp2", "F7", "F3", "Fz", "F4", "F8",
    "FC5", "FC1", "FC2", "FC6",
    "T7", "C3", "C4", "T8",
    "CP5", "CP1", "CP2", "CP6",
    "P7", "P3", "Pz", "P4", "P8",
    "PO9", "O1", "Oz", "O2", "PO10",
    "AF7", "AF3", "AF4", "AF8",
    "F5", "F1", "F2", "F6",
    "FT9", "FT7", "FC3", "FC4", "FT8", "FT10",
    "C5", "C1", "C2", "C6",
    "TP9", "TP7", "CP3", "CPz", "CP4", "TP8", "TP10",
    "P5", "P1", "P2", "P6",
    "PO7", "PO3", "PO4", "PO8",
]

STANDARD_10_10_32 = [
    "Cz",
    "Fp1", "Fpz", "Fp2", "F7", "F3", "Fz", "F4", "F8",
    "FC5", "FC1", "FC2", "FC6",
    "T7", "C3", "C4", "T8",
    "CP5", "CP1", "CP2", "CP6",
    "P7", "P3", "Pz", "P4", "P8",
    "PO9", "O1", "Oz", "O2", "PO10",
    "AFz",
]

STANDARD_10_20_21 = [
    "Cz",
    "Fp1", "Fp2", "F7", "F3", "Fz", "F4", "F8",
    "T7", "C3", "C4", "T8",
    "P7", "P3", "Pz", "P4", "P8",
    "O1", "Oz", "O2", "AFz",
]

STANDARD_10_20_32 = [
    "Cz",
    "Fp1", "Fp2", "F7", "F3", "Fz", "F4", "F8",
    "FC5", "FC1", "FC2", "FC6",
    "T7", "C3", "C4", "T8",
    "CP5", "CP1", "CP2", "CP6",
    "P7", "P3", "Pz", "P4", "P8",
    "PO3", "PO4", "O1", "Oz", "O2", "AF3", "AF4",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", required=True, choices=["input", "standard_10_10", "standard_10_20"])
    parser.add_argument("--electrode-count", required=True, type=int)
    parser.add_argument("--reference-electrode", default="Cz")
    parser.add_argument("--standard-1010-csv", required=True)
    parser.add_argument("--custom-csv", default="")
    parser.add_argument("--output-csv", required=True)
    return parser.parse_args()


def is_number(value: str) -> bool:
    try:
        float(value)
        return True
    except Exception:
        return False


def load_rows(path: Path) -> tuple[list[str] | None, list[list[str]]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        rows = [row for row in csv.reader(f) if row]
    if not rows:
        raise SystemExit(f"Empty EEG cap CSV: {path}")
    first = rows[0]
    header = None
    if len(first) >= 4 and (not is_number(first[1]) or not is_number(first[2]) or not is_number(first[3])):
        header = first
        rows = rows[1:]
    return header, rows


def name_column_index(header: list[str] | None) -> int:
    if header is None:
        return -1
    candidates = ["name", "label", "electrode", "channel"]
    lowered = [h.strip().lower() for h in header]
    for cand in candidates:
        if cand in lowered:
            return lowered.index(cand)
    return 0


def canonical(label: str) -> str:
    return label.strip().replace(" ", "").upper()


def infer_name_index(rows: list[list[str]], header: list[str] | None) -> int:
    idx = name_column_index(header)
    if idx >= 0:
        return idx
    if not rows:
        return 0
    first = rows[0]
    # SimNIBS standard electrode CSV rows look like:
    # Electrode,x,y,z,Fp1
    if len(first) >= 5 and canonical(first[0]) == "ELECTRODE":
        return len(first) - 1
    return 0


def desired_labels(mode: str, count: int) -> list[str]:
    if mode == "standard_10_10":
      mapping = {
          32: STANDARD_10_10_32,
          64: STANDARD_10_10_64,
      }
    elif mode == "standard_10_20":
      mapping = {
          21: STANDARD_10_20_21,
          32: STANDARD_10_20_32,
      }
    else:
      raise SystemExit(f"Unsupported standard mode: {mode}")
    if count not in mapping:
        raise SystemExit(f"Unsupported electrode count for {mode}: {count}")
    labels = mapping[count]
    if len(labels) != count:
        raise SystemExit(
            f"Internal electrode template mismatch for {mode}: "
            f"expected {count}, found {len(labels)}"
        )
    return labels


def write_rows(path: Path, header: list[str] | None, rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        if header is not None:
            writer.writerow(header)
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    reference = args.reference_electrode.strip()

    if args.mode == "input":
        if not args.custom_csv:
            raise SystemExit("Custom EEG cap CSV is required when --mode=input")
        source_path = Path(args.custom_csv)
    else:
        source_path = Path(args.standard_1010_csv)

    if not source_path.exists():
        raise SystemExit(f"EEG cap CSV not found: {source_path}")

    header, rows = load_rows(source_path)
    name_idx = infer_name_index(rows, header)
    row_map = {canonical(row[name_idx]): row for row in rows}

    if args.mode == "input":
        ordered_rows = rows[:]
        if len(ordered_rows) != args.electrode_count:
            raise SystemExit(
                f"Custom EEG cap row count ({len(ordered_rows)}) does not match requested "
                f"electrode count ({args.electrode_count})"
            )
    else:
        labels = desired_labels(args.mode, args.electrode_count)
        missing = [label for label in labels if canonical(label) not in row_map]
        if missing:
            raise SystemExit(f"Missing standard EEG labels in {source_path}: {missing}")
        ordered_rows = [row_map[canonical(label)] for label in labels]

    ordered_names = [row[name_idx].strip() for row in ordered_rows]
    if reference in ordered_names:
        ref_idx = ordered_names.index(reference)
        if ref_idx != 0:
            ordered_rows = [ordered_rows[ref_idx], *ordered_rows[:ref_idx], *ordered_rows[ref_idx + 1:]]

    write_rows(Path(args.output_csv), header, ordered_rows)


if __name__ == "__main__":
    main()
