#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
from pathlib import Path

import h5py
import nibabel as nib
import numpy as np
import pandas as pd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--leadfield-hdf5", required=True)
    parser.add_argument("--atlas", required=True)
    parser.add_argument("--labels-tsv", required=True)
    parser.add_argument("--cap-csv", required=True)
    parser.add_argument("--reference-electrode", default="Cz")
    parser.add_argument("--field", default="E")
    parser.add_argument("--output-68", required=True)
    parser.add_argument("--output-88", required=True)
    parser.add_argument("--output-qc", required=True)
    return parser.parse_args()


def is_number(value: str) -> bool:
    try:
        float(value)
        return True
    except Exception:
        return False


def load_cap_names(path: Path) -> list[str]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        rows = [row for row in csv.reader(f) if row]
    if not rows:
        raise SystemExit(f"Empty cap CSV: {path}")
    header = None
    if len(rows[0]) >= 4 and (not is_number(rows[0][1]) or not is_number(rows[0][2]) or not is_number(rows[0][3])):
        header = rows.pop(0)
    name_idx = 0
    if header is not None:
        lowered = [h.strip().lower() for h in header]
        for cand in ("name", "label", "electrode", "channel"):
            if cand in lowered:
                name_idx = lowered.index(cand)
                break
    return [row[name_idx].strip() for row in rows]


def walk_datasets(group: h5py.Group, prefix: str = "") -> list[tuple[str, h5py.Dataset]]:
    found: list[tuple[str, h5py.Dataset]] = []
    for key, value in group.items():
        current = f"{prefix}/{key}" if prefix else key
        if isinstance(value, h5py.Dataset):
            found.append((current, value))
        elif isinstance(value, h5py.Group):
            found.extend(walk_datasets(value, current))
    return found


def pick_dataset(datasets: list[tuple[str, h5py.Dataset]], names: set[str], ndim: int | None = None) -> np.ndarray | None:
    for path, ds in datasets:
        leaf = path.split("/")[-1].lower()
        if leaf in names and (ndim is None or ds.ndim == ndim):
            return np.asarray(ds)
    return None


def normalize_triangles(triangles: np.ndarray, n_nodes: int) -> np.ndarray | None:
    tri = np.asarray(triangles)
    if tri.ndim != 2 or tri.shape[1] < 3:
        return None
    tri = tri[:, :3].astype(np.int64, copy=False)
    if tri.min() >= 1 and tri.max() <= n_nodes:
        tri = tri - 1
    if tri.min() < 0 or tri.max() >= n_nodes:
        return None
    return tri


def normalize_leadfield(arr: np.ndarray, n_nodes: int, expected_sensors: int) -> np.ndarray:
    data = np.squeeze(np.asarray(arr))
    candidates: list[np.ndarray] = []

    if data.ndim == 3:
        for node_axis in range(3):
            if data.shape[node_axis] != n_nodes:
                continue
            for vec_axis in range(3):
                if vec_axis == node_axis or data.shape[vec_axis] != 3:
                    continue
                sensor_axis = ({0, 1, 2} - {node_axis, vec_axis}).pop()
                cand = np.transpose(data, (node_axis, vec_axis, sensor_axis))
                candidates.append(cand)

    if data.ndim == 2:
        if data.shape[0] == n_nodes and data.shape[1] % 3 == 0:
            sensors = data.shape[1] // 3
            candidates.append(data.reshape(n_nodes, sensors, 3).transpose(0, 2, 1))
        if data.shape[1] == n_nodes and data.shape[0] % 3 == 0:
            sensors = data.shape[0] // 3
            candidates.append(data.reshape(sensors, 3, n_nodes).transpose(2, 1, 0))
        if data.shape[0] in {expected_sensors, expected_sensors - 1} and data.shape[1] == n_nodes * 3:
            sensors = data.shape[0]
            candidates.append(data.reshape(sensors, n_nodes, 3).transpose(1, 2, 0))
        if data.shape[1] in {expected_sensors, expected_sensors - 1} and data.shape[0] == n_nodes * 3:
            sensors = data.shape[1]
            candidates.append(data.reshape(n_nodes, 3, sensors))

    if not candidates:
        raise SystemExit(f"Cannot normalize leadfield with shape {data.shape} for n_nodes={n_nodes}")

    def score(candidate: np.ndarray) -> tuple[int, int]:
        sensors = candidate.shape[2]
        if sensors == expected_sensors:
            return (0, sensors)
        if sensors == expected_sensors - 1:
            return (1, sensors)
        return (abs(sensors - expected_sensors) + 10, sensors)

    best = sorted(candidates, key=score)[0]
    return best


def compute_vertex_normals(coords: np.ndarray, triangles: np.ndarray | None) -> np.ndarray | None:
    if triangles is None or len(triangles) == 0:
        return None
    normals = np.zeros_like(coords, dtype=np.float64)
    tri_coords = coords[triangles]
    face_normals = np.cross(tri_coords[:, 1] - tri_coords[:, 0], tri_coords[:, 2] - tri_coords[:, 0])
    for i in range(3):
        np.add.at(normals, triangles[:, i], face_normals)
    lengths = np.linalg.norm(normals, axis=1)
    valid = lengths > 0
    if not np.any(valid):
        return None
    normals[valid] /= lengths[valid][:, None]
    return normals


def sample_volume_labels(coords: np.ndarray, atlas_img: nib.Nifti1Image) -> np.ndarray:
    data = np.asarray(atlas_img.dataobj)
    inv_aff = np.linalg.inv(atlas_img.affine)
    ijk = nib.affines.apply_affine(inv_aff, coords)
    ijk = np.rint(ijk).astype(int)
    labels = np.zeros(coords.shape[0], dtype=np.int32)
    valid = (
        (ijk[:, 0] >= 0) & (ijk[:, 0] < data.shape[0]) &
        (ijk[:, 1] >= 0) & (ijk[:, 1] < data.shape[1]) &
        (ijk[:, 2] >= 0) & (ijk[:, 2] < data.shape[2])
    )
    labels[valid] = data[ijk[valid, 0], ijk[valid, 1], ijk[valid, 2]].astype(np.int32)
    return labels


def voxel_centroid_world(atlas_data: np.ndarray, atlas_affine: np.ndarray, label_value: int) -> np.ndarray:
    vox = np.argwhere(atlas_data == label_value)
    if vox.size == 0:
        raise SystemExit(f"Atlas label {label_value} is missing from aparc+aseg volume")
    centroid_ijk = vox.mean(axis=0)
    return nib.affines.apply_affine(atlas_affine, centroid_ijk)


def restore_reference_row(matrix: np.ndarray, cap_names: list[str], reference: str) -> tuple[np.ndarray, list[str]]:
    if matrix.shape[0] == len(cap_names):
        return matrix, cap_names
    if matrix.shape[0] != len(cap_names) - 1:
        raise SystemExit(
            f"Leadfield sensor dimension ({matrix.shape[0]}) does not match cap rows "
            f"({len(cap_names)}) or cap rows - 1"
        )
    ref_idx = 0
    if reference in cap_names:
        ref_idx = cap_names.index(reference)
    full = np.zeros((len(cap_names), matrix.shape[1]), dtype=np.float64)
    full_indices = [i for i in range(len(cap_names)) if i != ref_idx]
    full[full_indices, :] = matrix
    return full, cap_names


def main() -> None:
    args = parse_args()

    cap_names = load_cap_names(Path(args.cap_csv))
    labels_df = pd.read_csv(args.labels_tsv, sep="\t")
    desikan_df = labels_df[labels_df["source"].astype(str).str.lower() == "desikan"].copy()
    if desikan_df.empty:
        raise SystemExit(f"No Desikan rows found in {args.labels_tsv}")

    with h5py.File(args.leadfield_hdf5, "r") as h5:
        datasets = walk_datasets(h5)
        leadfield_raw = pick_dataset(datasets, {"tdcs_leadfield"})
        node_coords = pick_dataset(datasets, {"node_coord", "node_coords", "coordinates"})
        triangles = pick_dataset(datasets, {"node_number_list", "triangles", "triangle_nodes"})
        if leadfield_raw is None:
            raise SystemExit(f"Cannot find tdcs_leadfield dataset in {args.leadfield_hdf5}")
        if node_coords is None:
            raise SystemExit(f"Cannot find node coordinates in {args.leadfield_hdf5}")

    coords = np.asarray(node_coords, dtype=np.float64)
    if coords.ndim != 2 or coords.shape[1] < 3:
        raise SystemExit(f"Unexpected node coordinate shape: {coords.shape}")
    coords = coords[:, :3]

    tri = normalize_triangles(triangles, coords.shape[0]) if triangles is not None else None
    leadfield = normalize_leadfield(leadfield_raw, coords.shape[0], len(cap_names))
    normals = compute_vertex_normals(coords, tri)
    if normals is not None and args.field.upper() == "E":
        scalar = np.einsum("nks,nk->ns", leadfield, normals)
        reduction_mode = "normal_projection"
    else:
        scalar = np.linalg.norm(leadfield, axis=1)
        reduction_mode = "vector_magnitude"

    atlas_img = nib.load(args.atlas)
    atlas_data = np.asarray(atlas_img.dataobj)
    sampled_labels = sample_volume_labels(coords, atlas_img)

    qc_rows: list[dict[str, object]] = []
    roi_vectors: list[np.ndarray] = []
    for row in desikan_df.itertuples(index=False):
        original_label = int(row.original_label)
        node_idx = np.flatnonzero(sampled_labels == original_label)
        used_fallback = 0
        if node_idx.size == 0:
            centroid = voxel_centroid_world(atlas_data, atlas_img.affine, original_label)
            node_idx = np.array([int(np.argmin(np.sum((coords - centroid) ** 2, axis=1)))], dtype=np.int64)
            used_fallback = 1
        roi_vec = scalar[node_idx].mean(axis=0)
        roi_vectors.append(roi_vec)
        qc_rows.append(
            {
                "index": int(row.index),
                "label": row.label,
                "abbreviation": row.abbreviation,
                "original_label": original_label,
                "node_count": int(node_idx.size),
                "used_fallback": used_fallback,
                "mean_abs_loading": float(np.mean(np.abs(roi_vec))),
            }
        )

    lf68 = np.stack(roi_vectors, axis=1)
    lf68, ordered_cap_names = restore_reference_row(lf68, cap_names, args.reference_electrode)

    lf88 = np.zeros((lf68.shape[0], len(labels_df)), dtype=np.float64)
    desikan_positions = desikan_df.index.to_numpy()
    lf88[:, desikan_positions] = lf68

    col68 = desikan_df["abbreviation"].tolist()
    col88 = labels_df["abbreviation"].tolist()
    df68 = pd.DataFrame(lf68, index=ordered_cap_names, columns=col68)
    df88 = pd.DataFrame(lf88, index=ordered_cap_names, columns=col88)

    Path(args.output_68).parent.mkdir(parents=True, exist_ok=True)
    df68.to_csv(args.output_68, float_format="%.8f")
    df88.to_csv(args.output_88, float_format="%.8f")

    qc_df = pd.DataFrame(qc_rows)
    qc_df.insert(0, "reduction_mode", reduction_mode)
    qc_df.to_csv(args.output_qc, sep="\t", index=False)


if __name__ == "__main__":
    main()
