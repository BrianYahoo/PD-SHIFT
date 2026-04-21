#!/usr/bin/env python3
import argparse
from pathlib import Path

import nibabel as nib
import numpy as np


def load_image(path):
    return nib.load(str(path))


def max_fov_vox(shape, zooms, max_fov_mm):
    return [int(np.floor((max_fov_mm + 1e-6) / float(z))) for z in zooms]


def clamp_window(center, size, limit):
    start = int(round(center - size / 2.0))
    start = max(0, min(start, limit - size))
    return start, start + size


def compute_crop_slices(mask_img, ref_img, margin_vox, max_fov_mm):
    mask = np.asarray(mask_img.dataobj) > 0
    shape = ref_img.shape[:3]
    zooms = ref_img.header.get_zooms()[:3]
    limits = max_fov_vox(shape, zooms, max_fov_mm)
    mins = [0, 0, 0]
    maxs = list(shape)

    if mask.any():
      coords = np.argwhere(mask)
      mins = coords.min(axis=0).tolist()
      maxs = (coords.max(axis=0) + 1).tolist()

    slices = []
    changed = False
    for axis, dim in enumerate(shape):
        limit = limits[axis]
        if dim <= limit:
            slices.append(slice(0, dim))
            continue

        changed = True
        roi_start = max(0, mins[axis] - margin_vox)
        roi_stop = min(dim, maxs[axis] + margin_vox)
        roi_size = roi_stop - roi_start

        if roi_size <= limit:
            center = (roi_start + roi_stop) / 2.0
            start, stop = clamp_window(center, limit, dim)
        else:
            center = (mins[axis] + maxs[axis]) / 2.0
            start, stop = clamp_window(center, limit, dim)
        slices.append(slice(start, stop))
    return tuple(slices), changed


def crop_and_save(src_path, dst_path, crop_slices):
    img = load_image(src_path)
    data = np.asanyarray(img.dataobj)
    cropped = data[crop_slices + ((slice(None),) if data.ndim > 3 else tuple())]
    affine = img.affine.copy()
    offset = np.array([crop_slices[0].start, crop_slices[1].start, crop_slices[2].start, 1.0])
    affine[:3, 3] = (img.affine @ offset)[:3]
    out = nib.Nifti1Image(cropped, affine, img.header.copy())
    out.set_qform(affine, code=int(img.header["qform_code"]))
    out.set_sform(affine, code=int(img.header["sform_code"]))
    nib.save(out, str(dst_path))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--t1", required=True)
    parser.add_argument("--mask", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--brain")
    parser.add_argument("--fs-brain")
    parser.add_argument("--xmask")
    parser.add_argument("--t2")
    parser.add_argument("--max-fov-mm", type=float, default=256.0)
    parser.add_argument("--margin-vox", type=int, default=8)
    args = parser.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    t1_img = load_image(args.t1)
    mask_img = load_image(args.mask)
    crop_slices, changed = compute_crop_slices(mask_img, t1_img, args.margin_vox, args.max_fov_mm)

    mapping = {
        "t1": args.t1,
        "brain": args.brain,
        "fs_brain": args.fs_brain,
        "xmask": args.xmask,
        "t2": args.t2,
        "mask": args.mask,
    }

    outputs = {}
    for key, src in mapping.items():
        if not src:
            continue
        src_path = Path(src)
        suffix = "".join(src_path.suffixes)
        stem = src_path.name[: -len(suffix)] if suffix else src_path.name
        dst = out_dir / f"{stem}_cropped{suffix}"
        if changed:
            crop_and_save(src_path, dst, crop_slices)
        else:
            dst = src_path
        outputs[key] = str(dst)

    shape = t1_img.shape[:3]
    zooms = t1_img.header.get_zooms()[:3]
    cropped_shape = load_image(outputs["t1"]).shape[:3]
    print(f"crop_applied={1 if changed else 0}")
    print(f"orig_shape={shape[0]},{shape[1]},{shape[2]}")
    print(f"cropped_shape={cropped_shape[0]},{cropped_shape[1]},{cropped_shape[2]}")
    print(f"zooms_mm={float(zooms[0]):.6f},{float(zooms[1]):.6f},{float(zooms[2]):.6f}")
    print(
        f"crop_bounds={crop_slices[0].start}:{crop_slices[0].stop},"
        f"{crop_slices[1].start}:{crop_slices[1].stop},"
        f"{crop_slices[2].start}:{crop_slices[2].stop}"
    )
    for key, value in outputs.items():
        print(f"{key}_path={value}")


if __name__ == "__main__":
    main()
