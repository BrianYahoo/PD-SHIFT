#!/usr/bin/env python3
"""比较 pipeline 输出与参考 FC / SC 矩阵。"""

import argparse
import csv
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns


def parse_args():
    """解析命令行参数。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--final-dir", required=True)
    parser.add_argument("--subject-id", required=True)
    parser.add_argument("--dataset-type", required=True, choices=["hcp", "parkinson"])
    parser.add_argument("--fc-reference-root", required=True)
    parser.add_argument("--sc-reference-root", required=True)
    parser.add_argument("--out-dir", required=True)
    return parser.parse_args()


def load_matrix(path: Path):
    """读取矩阵文件。"""
    return np.loadtxt(path, delimiter=",").astype(float)


def upper_tri(mat):
    """提取上三角非对角元素。"""
    tri = np.triu_indices_from(mat, k=1)
    return mat[tri]


def safe_pearson(x, y):
    """计算稳健 Pearson 相关。"""
    if x.size < 2 or np.std(x) < 1e-12 or np.std(y) < 1e-12:
        return float("nan")
    return float(np.corrcoef(x, y)[0, 1])


def plot_pair(subject, reference, title, save_path):
    """输出两张矩阵及非对角元素回归图。"""
    vals = np.concatenate([subject.ravel(), reference.ravel()])
    vmin = np.nanpercentile(vals, 1)
    vmax = np.nanpercentile(vals, 99)
    fig, axes = plt.subplots(1, 3, figsize=(12.5, 4.2), constrained_layout=True)
    im0 = axes[0].imshow(subject, cmap="RdBu_r", vmin=vmin, vmax=vmax)
    axes[0].set_title(f"{title} subject")
    axes[0].set_xticks([])
    axes[0].set_yticks([])
    axes[1].imshow(reference, cmap="RdBu_r", vmin=vmin, vmax=vmax)
    axes[1].set_title(f"{title} reference")
    axes[1].set_xticks([])
    axes[1].set_yticks([])
    fig.colorbar(im0, ax=[axes[0], axes[1]], fraction=0.046, pad=0.02)

    x = upper_tri(subject)
    y = upper_tri(reference)
    valid = np.isfinite(x) & np.isfinite(y)
    x = x[valid]
    y = y[valid]
    sns.regplot(x=x, y=y, ax=axes[2], ci=None, scatter_kws={"s": 10, "alpha": 0.5}, line_kws={"color": "#D62728"})
    r = safe_pearson(x, y)
    axes[2].set_title(f"{title} r={r:.3f}")
    axes[2].set_xlabel("subject")
    axes[2].set_ylabel("reference")
    fig.savefig(save_path, dpi=300, bbox_inches="tight", pad_inches=0.08)
    plt.close(fig)
    return r, int(valid.sum())


def sc_scale_title(scale: str):
    """把 SC 分层名称压缩成更短的标题缩写。"""
    title_map = {
        "whole_brain": "SC WB",
        "cortical": "SC CTX",
        "subcortical": "SC SUB",
    }
    return title_map.get(scale, f"SC {scale}")


def transform_sc(mat: np.ndarray, mode: str):
    """按指定方式对 SC 矩阵做统一变换。"""
    if mode == "log1p":
        return np.log1p(mat)
    if mode == "max1":
        max_val = float(np.nanmax(mat))
        if not np.isfinite(max_val) or max_val <= 0:
            return mat.copy()
        return mat / max_val
    raise ValueError(f"Unsupported SC transform: {mode}")


def load_trial_names(final_dir: Path):
    """从 trial 表中读取当前受试者的全部 fMRI trial。"""
    rows = list(csv.DictReader((final_dir / "func" / "fmri_trials.tsv").open("r", encoding="utf-8"), delimiter="\t"))
    return [row["trial_name"] for row in rows]


def load_hcp_trial_fc_reference(fc_root: Path, subject_key: str, trial_name: str):
    """加载 HCP 某个 trial 的 individual FC reference。"""
    ref_path = fc_root / "preprocessed" / "Atlas_MSMAll" / "individual" / subject_key / trial_name / "cortical" / "fc.npy"
    if not ref_path.exists():
        raise FileNotFoundError(ref_path)
    return np.load(ref_path).astype(float), str(ref_path)


def load_hcp_average_fc_reference(fc_root: Path, subject_key: str):
    """加载 HCP 某个 subject 的 average cortical FC reference。"""
    ref_path = fc_root / "preprocessed" / "Atlas_MSMAll" / "individual" / subject_key / "average" / "cortical" / "fc.npy"
    if not ref_path.exists():
        raise FileNotFoundError(ref_path)
    return np.load(ref_path).astype(float), str(ref_path)


def load_parkinson_fc_reference(fc_root: Path):
    """加载 Parkinson 使用的 HCP group FC reference。"""
    ref_path = fc_root / "preprocessed" / "Atlas_MSMAll" / "group" / "fc.npy"
    if not ref_path.exists():
        raise FileNotFoundError(ref_path)
    return np.load(ref_path).astype(float), str(ref_path)


def load_sc_reference(sc_root: Path):
    """加载 TVP 的三类 SC 参考并求和。"""
    ref = (
        np.load(sc_root / "conn_excitator.npy").astype(float)
        + np.load(sc_root / "conn_inhibitor.npy").astype(float)
        + np.load(sc_root / "conn_dopamine.npy").astype(float)
    )
    return 0.5 * (ref + ref.T)


def load_trial_bbr_fc(final_dir: Path, subject_id: str, trial_name: str):
    """读取单个 trial 的 BBR FC。"""
    fc_path = final_dir / "func" / "fc_bbr" / f"{subject_id}_{trial_name}_step5_bbr_fc_pearson.csv"
    if not fc_path.exists():
        raise FileNotFoundError(fc_path)
    return load_matrix(fc_path), str(fc_path)


def main():
    """执行 FC / SC 对比并写出指标与图像。"""
    args = parse_args()
    final_dir = Path(args.final_dir)
    out_dir = Path(args.out_dir)
    fc_dir = out_dir / "fc"
    sc_dir = out_dir / "sc"
    fc_dir.mkdir(parents=True, exist_ok=True)
    sc_dir.mkdir(parents=True, exist_ok=True)

    labels_df = pd.read_csv(final_dir / f"{args.subject_id}_labels.tsv", sep="\t")
    fc_final = load_matrix(final_dir / f"{args.subject_id}_FC_pearson.csv")
    fc_bbr = load_matrix(final_dir / f"{args.subject_id}_FC_bbr_pearson.csv")
    sc = load_matrix(final_dir / f"{args.subject_id}_DTI_connectome_sift2.csv")

    tvp_labels = labels_df["label (TVP)"].astype(str).tolist()
    source_labels = labels_df["source"].astype(str).str.lower().tolist()

    cortical_idx = [i for i, src in enumerate(source_labels) if src == "desikan"]
    subject_fc_full = fc_bbr
    subject_fc_name = "BBR FC"

    subject_fc_cortical = subject_fc_full[np.ix_(cortical_idx, cortical_idx)]
    trial_names = load_trial_names(final_dir)

    metrics = []
    fc_reference_root = Path(args.fc_reference_root)
    subject_key = args.subject_id.removeprefix("sub-")

    if args.dataset_type == "hcp":
        for trial_name in trial_names:
            trial_subject_fc_full, trial_subject_fc_path = load_trial_bbr_fc(final_dir, args.subject_id, trial_name)
            trial_subject_fc = trial_subject_fc_full[np.ix_(cortical_idx, cortical_idx)]
            trial_ref_fc, trial_ref_path = load_hcp_trial_fc_reference(fc_reference_root, subject_key, trial_name)
            fc_png = fc_dir / f"{args.subject_id}_{trial_name}_fc_compare.png"
            r, n_edges = plot_pair(trial_subject_fc, trial_ref_fc, f"FC cortical {trial_name}", fc_png)
            metrics.append(
                {
                    "modality": "FC",
                    "comparison_level": "trial",
                    "trial_name": trial_name,
                    "subject_fc": "BBR FC",
                    "subject_fc_path": trial_subject_fc_path,
                    "reference": f"HCP individual trial ({subject_key}; {trial_name})",
                    "reference_path": trial_ref_path,
                    "scale": "cortical",
                    "r": r,
                    "n_edges": n_edges,
                    "figure": str(fc_png),
                }
            )

        ref_fc, ref_path = load_hcp_average_fc_reference(fc_reference_root, subject_key)
        fc_ref_name = f"HCP individual average ({ref_path})"
        fc_png = fc_dir / f"{args.subject_id}_fc_compare.png"
        r, n_edges = plot_pair(subject_fc_cortical, ref_fc, "FC cortical average", fc_png)
        metrics.append(
            {
                "modality": "FC",
                "comparison_level": "average",
                "trial_name": "average",
                "subject_fc": subject_fc_name,
                "subject_fc_path": str(final_dir / f"{args.subject_id}_FC_bbr_pearson.csv"),
                "reference": fc_ref_name,
                "reference_path": ref_path,
                "scale": "cortical",
                "r": r,
                "n_edges": n_edges,
                "figure": str(fc_png),
            }
        )
    else:
        ref_fc, ref_path = load_parkinson_fc_reference(fc_reference_root)
        fc_ref_name = f"HCP group ({ref_path})"
        fc_png = fc_dir / f"{args.subject_id}_fc_compare.png"
        r, n_edges = plot_pair(subject_fc_cortical, ref_fc, "FC cortical", fc_png)
        metrics.append(
            {
                "modality": "FC",
                "comparison_level": "group",
                "trial_name": "average",
                "subject_fc": subject_fc_name,
                "subject_fc_path": str(final_dir / f"{args.subject_id}_FC_bbr_pearson.csv"),
                "reference": fc_ref_name,
                "reference_path": ref_path,
                "scale": "cortical",
                "r": r,
                "n_edges": n_edges,
                "figure": str(fc_png),
            }
        )

    sc_reference_root = Path(args.sc_reference_root)
    sc_ref = load_sc_reference(sc_reference_root)
    common_labels = tvp_labels
    subject_idx = list(range(len(common_labels)))
    ref_idx = list(range(len(common_labels)))
    sc_ref_common = sc_ref[np.ix_(ref_idx, ref_idx)]

    subcortical_idx = [i for i, src in enumerate(source_labels) if src == "subcortical"]
    scale_map = {
        "whole_brain": list(range(len(common_labels))),
        "cortical": [i for i in range(len(common_labels)) if subject_idx[i] in cortical_idx],
        "subcortical": [i for i in range(len(common_labels)) if subject_idx[i] in subcortical_idx],
    }

    sc_inputs = [
        ("sift2", sc, str(final_dir / f"{args.subject_id}_DTI_connectome_sift2.csv")),
        ("count", load_matrix(final_dir / f"{args.subject_id}_DTI_connectome_count.csv"), str(final_dir / f"{args.subject_id}_DTI_connectome_count.csv")),
    ]

    for sc_type, sc_variant, sc_path in sc_inputs:
        sc_type_dir = sc_dir / sc_type
        sc_type_dir.mkdir(parents=True, exist_ok=True)
        sc_subject_common = sc_variant[np.ix_(subject_idx, subject_idx)]

        for transform_name in ("log1p", "max1"):
            transform_dir = sc_type_dir / transform_name
            transform_dir.mkdir(parents=True, exist_ok=True)
            sc_subject_x = transform_sc(sc_subject_common, transform_name)
            sc_ref_x = transform_sc(sc_ref_common, transform_name)

            for scale, idx_list in scale_map.items():
                if len(idx_list) < 2:
                    continue
                idx = np.asarray(idx_list, dtype=int)
                sub = sc_subject_x[np.ix_(idx, idx)]
                ref = sc_ref_x[np.ix_(idx, idx)]
                out_png = transform_dir / f"{args.subject_id}_{scale}_sc_compare.png"
                r, n_edges = plot_pair(sub, ref, sc_scale_title(scale), out_png)
                metrics.append(
                    {
                        "modality": "SC",
                        "comparison_level": sc_type,
                        "transform": transform_name,
                        "subject_sc_path": sc_path,
                        "reference": "TVP",
                        "scale": scale,
                        "n_nodes": int(len(idx_list)),
                        "r": r,
                        "n_edges": n_edges,
                        "figure": str(out_png),
                    }
                )

    metrics_df = pd.DataFrame(metrics)
    metrics_df.to_csv(out_dir / "summary_metrics.csv", index=False)
    (out_dir / "summary_metrics.json").write_text(metrics_df.to_json(orient="records", indent=2), encoding="utf-8")

    lines = [f"# Reference Comparison ({args.subject_id})", "", "## Metrics", "```text", metrics_df.to_string(index=False), "```", ""]
    (out_dir / "summary.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
