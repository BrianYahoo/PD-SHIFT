#!/usr/bin/env python3
"""批量修正历史 fMRI 头动与 scrubbing 相关产物。

只刷新已经存在的输出文件，不调用任何 phase shell 脚本。
目的：
1. 修正 mcflirt .par 列顺序误读导致的 FD 偏大问题。
2. 重绘 motion_metrics.png，并写入正确单位。
3. 重算 step10 的 FD / scrub mask / scrub qc / toxic nifti。
4. 同步更新 trial 级 FC_qc 中嵌入的 scrub 信息。
5. 如果 phase4_summary 已完成，则同步覆盖 final 目录中的 FD / scrub / FC_qc 副本，
   并重写 reports/fmri_trials_qc.json。
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import nibabel as nib
import numpy as np

UTILS_ROOT = Path(__file__).resolve().parents[2]
if str(UTILS_ROOT) not in sys.path:
    sys.path.insert(0, str(UTILS_ROOT))

from phase2_fmri.shared.fmri_utils import load_motion, power_fd
from phase2_fmri.step10.fmri_scrubbing import build_toxic_mask
from phase2_fmri.step4.plot_motion_metrics import main as _unused  # noqa: F401

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


PIPELINE_ENV = Path("/data/bryang/project/CNS/pipeline/config/pipeline.env")


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--roots",
        nargs="+",
        default=[
            "/data/bryang/project/CNS/data/HCP/workspace",
            "/data/bryang/project/CNS/data/Parkinson/workspace",
        ],
    )
    return parser.parse_args()


def load_env_config(path: Path):
    cfg = {}
    if not path.exists():
        return cfg
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        cfg[key.strip()] = value.strip().strip('"').strip("'")
    return cfg


def draw_motion_plot(motion, fd, png_path: Path, fd_threshold: float):
    rotation_deg = np.rad2deg(motion[:, 3:])
    fig, axes = plt.subplots(3, 1, figsize=(12, 8), dpi=150, sharex=True)
    x = np.arange(motion.shape[0])

    axes[0].plot(x, motion[:, 0], label="X")
    axes[0].plot(x, motion[:, 1], label="Y")
    axes[0].plot(x, motion[:, 2], label="Z")
    axes[0].set_ylabel("Translation (mm)")
    axes[0].set_title("Head Motion: Translation (mm)")
    axes[0].legend(loc="upper right", ncol=3, fontsize=8)

    axes[1].plot(x, rotation_deg[:, 0], label="RotX")
    axes[1].plot(x, rotation_deg[:, 1], label="RotY")
    axes[1].plot(x, rotation_deg[:, 2], label="RotZ")
    axes[1].set_ylabel("Rotation (degree)")
    axes[1].set_title("Head Motion: Rotation (degree)")
    axes[1].legend(loc="upper right", ncol=3, fontsize=8)

    axes[2].plot(x, fd, color="black", linewidth=1.0, label="FD")
    axes[2].axhline(fd_threshold, color="red", linestyle="--", linewidth=1.0, label=f"FD={fd_threshold:.2f}")
    axes[2].set_xlabel("Frame")
    axes[2].set_ylabel("FD (mm)")
    axes[2].set_title("Power FD (mm)")
    axes[2].legend(loc="upper right", fontsize=8)

    for ax in axes:
        ax.grid(True, alpha=0.2)

    fig.tight_layout()
    png_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(png_path, bbox_inches="tight")
    plt.close(fig)


def update_toxic_nifti(func_path: Path, brain_mask_path: Path, toxic: np.ndarray, out_path: Path):
    func_img = nib.load(str(func_path))
    if brain_mask_path.exists():
        brain_mask = np.asarray(nib.load(str(brain_mask_path)).dataobj, dtype=np.float32) > 0.5
    else:
        brain_mask = np.abs(np.asarray(func_img.dataobj[:, :, :, 0], dtype=np.float32)) > 0
    toxic_img = np.zeros(func_img.shape, dtype=np.uint8)
    for z_idx in range(func_img.shape[2]):
        toxic_img[:, :, z_idx, :] = brain_mask[:, :, z_idx][:, :, None].astype(np.uint8) * toxic.astype(np.uint8)[None, None, :]
    out_img = nib.Nifti1Image(toxic_img, func_img.affine, func_img.header)
    out_img.set_data_dtype(np.uint8)
    nib.save(out_img, str(out_path))


def update_fc_qc(fc_qc_path: Path, scrub_qc_path: Path):
    if not fc_qc_path.exists() or not scrub_qc_path.exists():
        return False
    qc = json.loads(fc_qc_path.read_text(encoding="utf-8"))
    scrub = json.loads(scrub_qc_path.read_text(encoding="utf-8"))
    qc["scrub"] = scrub
    fc_qc_path.write_text(json.dumps(qc, indent=2, ensure_ascii=False), encoding="utf-8")
    return True


def update_summary_trial_qc(subject_root: Path):
    final_dir = subject_root / "phases" / "phase4_summary" / "final"
    reports_dir = subject_root / "phases" / "phase4_summary" / "reports"
    trials_tsv = final_dir / "func" / "fmri_trials.tsv"
    out_qc = reports_dir / "fmri_trials_qc.json"
    if not trials_tsv.exists():
        return False
    rows = list(csv.DictReader(trials_tsv.open("r", encoding="utf-8"), delimiter="\t"))
    qc_rows = []
    for row in rows:
        qc_path = Path(row["qc_json"])
        qc_data = {}
        if qc_path.exists():
            qc_data = json.loads(qc_path.read_text(encoding="utf-8"))
        qc_rows.append({"trial_name": row["trial_name"], "qc": qc_data})
    out_qc.write_text(json.dumps(qc_rows, indent=2, ensure_ascii=False), encoding="utf-8")
    return True


def iter_trial_dirs(root: Path):
    pattern = "*/derivatives/cns-pipeline/sub-*/phases/phase2_fmri/*"
    for p in root.glob(pattern):
        if not p.is_dir():
            continue
        if p.name in {"visualization", "stepview"}:
            continue
        if (p / "func_mc.par").exists() and list(p.glob("*_FC_qc.json")):
            yield p


def update_trial(trial_dir: Path, cfg):
    subject_id = trial_dir.parent.parent.parent.name
    trial_name = trial_dir.name
    phase2_dir = trial_dir.parent
    phases_root = phase2_dir.parent
    subject_work_root = trial_dir.parents[5]
    motion_path = trial_dir / "func_mc.par"
    func_filter = trial_dir / "func_filter.nii.gz"
    brain_mask = trial_dir / "gs_mask_func.nii.gz"
    fd_threshold = float(cfg.get("FMRI_FD_THRESHOLD", "0.5"))
    scrub_before = int(cfg.get("FMRI_SCRUB_BEFORE", "0"))
    scrub_after = int(cfg.get("FMRI_SCRUB_AFTER", "0"))
    scrub_enabled = int(cfg.get("FMRI_ENABLE_SCRUBBING", "0"))

    raw = np.loadtxt(motion_path, dtype=float)
    if raw.ndim == 1:
        raw = raw[:, None]
    n_tp = raw.shape[0]
    motion = load_motion(str(motion_path), n_tp)
    fd = power_fd(motion)

    motion_vis_dir = subject_work_root / "visualization" / "phase2_fmri" / trial_name / "motion"
    motion_png = motion_vis_dir / "motion_metrics.png"
    motion_fd = motion_vis_dir / "framewise_displacement.tsv"
    draw_motion_plot(motion, fd, motion_png, fd_threshold)
    np.savetxt(motion_fd, fd, fmt="%.8f")

    fd_txt = trial_dir / f"{subject_id}_{trial_name}_FD_power.txt"
    scrub_txt = trial_dir / f"{subject_id}_{trial_name}_scrub_mask.txt"
    scrub_qc = trial_dir / f"{subject_id}_{trial_name}_scrub_qc.json"
    toxic_nii = trial_dir / "toxic_frames.nii.gz"

    suggested_toxic = build_toxic_mask(fd, fd_threshold, scrub_before, scrub_after)
    toxic = suggested_toxic if scrub_enabled else np.zeros_like(suggested_toxic, dtype=bool)

    np.savetxt(fd_txt, fd, fmt="%.8f")
    np.savetxt(scrub_txt, toxic.astype(int), fmt="%d")
    if func_filter.exists():
        update_toxic_nifti(func_filter, brain_mask, toxic, toxic_nii)

    scrub_payload = {
        "enabled": bool(scrub_enabled),
        "fd_threshold": float(fd_threshold),
        "n_timepoints": int(fd.shape[0]),
        "fd_mean": float(np.mean(fd)),
        "fd_max": float(np.max(fd)),
        "toxic_count": int(np.count_nonzero(toxic)),
        "toxic_indices": [int(i) for i in np.where(toxic)[0].tolist()],
        "suggested_toxic_count": int(np.count_nonzero(suggested_toxic)),
        "suggested_toxic_indices": [int(i) for i in np.where(suggested_toxic)[0].tolist()],
    }
    scrub_qc.write_text(json.dumps(scrub_payload, indent=2, ensure_ascii=False), encoding="utf-8")

    fc_qc = trial_dir / f"{subject_id}_{trial_name}_FC_qc.json"
    update_fc_qc(fc_qc, scrub_qc)

    final_dir = phases_root / "phase4_summary" / "final"
    final_fc_dir = final_dir / "func" / "fc"
    if final_fc_dir.exists():
        final_fd = final_fc_dir / fd_txt.name
        final_scrub = final_fc_dir / scrub_txt.name
        final_qc = final_fc_dir / fc_qc.name
        if final_fd.exists():
            np.savetxt(final_fd, fd, fmt="%.8f")
        if final_scrub.exists():
            np.savetxt(final_scrub, toxic.astype(int), fmt="%d")
        if final_qc.exists() and fc_qc.exists():
            final_qc.write_text(fc_qc.read_text(encoding="utf-8"), encoding="utf-8")

    return {
        "subject_id": subject_id,
        "trial_name": trial_name,
        "motion_png": str(motion_png),
        "fd_txt": str(fd_txt),
        "scrub_qc": str(scrub_qc),
    }


def main():
    args = parse_args()
    cfg = load_env_config(PIPELINE_ENV)
    updated = 0
    touched_subjects = set()

    for root_str in args.roots:
        root = Path(root_str)
        if not root.exists():
            continue
        for trial_dir in iter_trial_dirs(root):
            info = update_trial(trial_dir, cfg)
            touched_subjects.add(trial_dir.parent.parent.parent)
            updated += 1
            print(f"updated\t{info['subject_id']}\t{info['trial_name']}\t{info['motion_png']}")

    summary_updates = 0
    for subject_root in sorted(touched_subjects):
        if update_summary_trial_qc(subject_root):
            summary_updates += 1

    print(f"updated_trials\t{updated}")
    print(f"updated_subject_reports\t{summary_updates}")


if __name__ == "__main__":
    main()
