#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config
# 加载 conda、FSL、FreeSurfer、ANTs 等工具环境。
setup_tools_env

# 定义 summary 需要汇总的主要输入路径。
ATLAS_NII="${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz"
LABELS_TSV="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"

SC_SIFT2="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv"
SC_SIFT2_INVNODEVOL="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv"
SC_COUNT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv"
SC_COUNT_INVNODEVOL="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv"

SC_SIFT2_RADIAL4="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv"
SC_SIFT2_INVNODEVOL_RADIAL4="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv"
SC_COUNT_RADIAL4="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv"
SC_COUNT_INVNODEVOL_RADIAL4="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv"

SC_TYPED_MANIFEST="${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_typed_manifest.tsv"
SC_TYPED_QC="${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_typed_qc.json"
FMRI_TRIALS_TSV="${FINAL_DIR}/func/fmri_trials.tsv"
FMRI_TRIALS_QC_JSON="${REPORTS_DIR}/fmri_trials_qc.json"
STEP1_MANIFEST="${REPORTS_DIR}/step1_collect_outputs_manifest.tsv"

# 检查 summary 所依赖的关键产物是否都存在。
[[ -f "$ATLAS_NII" ]] || die "Missing atlas output"
[[ -f "$SC_SIFT2" ]] || die "Missing SC sift2 output"
[[ -f "$SC_SIFT2_INVNODEVOL" ]] || die "Missing SC sift2 invnodevol output"
[[ -f "$SC_COUNT" ]] || die "Missing SC count output"
[[ -f "$SC_COUNT_INVNODEVOL" ]] || die "Missing SC count invnodevol output"
[[ -f "$SC_SIFT2_RADIAL4" ]] || die "Missing SC radial4 sift2 output"
[[ -f "$SC_SIFT2_INVNODEVOL_RADIAL4" ]] || die "Missing SC radial4 sift2 invnodevol output"
[[ -f "$SC_COUNT_RADIAL4" ]] || die "Missing SC radial4 count output"
[[ -f "$SC_COUNT_INVNODEVOL_RADIAL4" ]] || die "Missing SC radial4 count invnodevol output"

# 如果汇总产物已经齐全，则直接跳过。
if [[ -f "${FINAL_DIR}/atlas/${SUBJECT_ID}_desc-custom_dseg.nii.gz" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_labels.tsv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_pearson.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_fisherz.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_FC_pearson.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_FC_fisherz.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv" \
   && -f "${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv" \
   && -f "${SC_TYPED_MANIFEST}" \
   && -f "${SC_TYPED_QC}" \
   && -f "${FMRI_TRIALS_TSV}" \
   && -f "${FMRI_TRIALS_QC_JSON}" \
   && -f "${STEP1_MANIFEST}" ]]; then
  log "[phase4_summary] Step1 already done for ${SUBJECT_ID}"
  exit 0
fi

# 读取当前受试者可用的所有 REST trial。
mapfile -t FMRI_TRIALS < <(list_fmri_trial_names)
(( ${#FMRI_TRIALS[@]} > 0 )) || die "No fMRI trials found for ${SUBJECT_ID}"

# 创建最终汇总目录树。
mkdir -p \
  "${FINAL_DIR}/atlas" \
  "${FINAL_DIR}/func/timeseries" \
  "${FINAL_DIR}/func/fc" \
  "${FINAL_DIR}/func/fc_bbr" \
  "${FINAL_DIR}/dwi/sc" \
  "${REPORTS_DIR}" \
  "${COMPARE_DIR}"

# 复制 atlas 和标签表到 final 目录。
cp -f "$ATLAS_NII" "${FINAL_DIR}/atlas/"
cp -f "$LABELS_TSV" "${FINAL_DIR}/${SUBJECT_ID}_labels.tsv"

# 为每个 trial 的 FC 结果写总清单。
cat > "$FMRI_TRIALS_TSV" <<EOF
trial_name	fc_pearson	fc_fisherz	fc_bbr_pearson	fc_bbr_fisherz	timeseries	qc_json	fd_txt	scrub_txt
EOF

# 依次复制每个 trial 的 FC、timeseries 和 QC 文件。
for trial_name in "${FMRI_TRIALS[@]}"; do
  trial_fmri_dir="${FMRI_ROOT_DIR}/${trial_name}"
  trial_fc_r="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_pearson.csv"
  trial_fc_z="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_fisherz.csv"
  trial_fc_bbr_r="${trial_fmri_dir}/stepresult/step5_bbr_fc_pearson.csv"
  trial_fc_bbr_z="${trial_fmri_dir}/stepresult/step5_bbr_fc_fisherz.csv"
  trial_fc_ts="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_timeseries.tsv"
  trial_fc_qc="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_qc.json"
  trial_fd_txt="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FD_power.txt"
  trial_scrub_txt="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_scrub_mask.txt"

  [[ -f "$trial_fc_r" ]] || die "Missing FC output for ${trial_name}"
  [[ -f "$trial_fc_z" ]] || die "Missing FC z output for ${trial_name}"
  [[ -f "$trial_fc_bbr_r" ]] || die "Missing BBR FC output for ${trial_name}"
  [[ -f "$trial_fc_bbr_z" ]] || die "Missing BBR FC z output for ${trial_name}"
  [[ -f "$trial_fc_ts" ]] || die "Missing FC timeseries for ${trial_name}"

  cp -f "$trial_fc_r" "${FINAL_DIR}/func/fc/"
  cp -f "$trial_fc_z" "${FINAL_DIR}/func/fc/"
  cp -f "$trial_fc_bbr_r" "${FINAL_DIR}/func/fc_bbr/${SUBJECT_ID}_${trial_name}_step5_bbr_fc_pearson.csv"
  cp -f "$trial_fc_bbr_z" "${FINAL_DIR}/func/fc_bbr/${SUBJECT_ID}_${trial_name}_step5_bbr_fc_fisherz.csv"
  cp -f "$trial_fc_qc" "${FINAL_DIR}/func/fc/"
  cp -f "$trial_fd_txt" "${FINAL_DIR}/func/fc/"
  cp -f "$trial_scrub_txt" "${FINAL_DIR}/func/fc/"
  cp -f "$trial_fc_ts" "${FINAL_DIR}/func/timeseries/"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$trial_name" \
    "$trial_fc_r" \
    "$trial_fc_z" \
    "$trial_fc_bbr_r" \
    "$trial_fc_bbr_z" \
    "$trial_fc_ts" \
    "$trial_fc_qc" \
    "$trial_fd_txt" \
    "$trial_scrub_txt" >> "$FMRI_TRIALS_TSV"
done

# 将全部 trial 的 FC 矩阵取平均，并汇总每个 trial 的 QC。
"$PYTHON_BIN" - "$FMRI_TRIALS_TSV" \
  "${FINAL_DIR}/${SUBJECT_ID}_FC_pearson.csv" \
  "${FINAL_DIR}/${SUBJECT_ID}_FC_fisherz.csv" \
  "${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_pearson.csv" \
  "${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_fisherz.csv" \
  "$FMRI_TRIALS_QC_JSON" <<'PY'
import csv
import json
import sys
from pathlib import Path

import numpy as np

trials_tsv = Path(sys.argv[1])
out_fc_r = Path(sys.argv[2])
out_fc_z = Path(sys.argv[3])
out_fc_bbr_r = Path(sys.argv[4])
out_fc_bbr_z = Path(sys.argv[5])
out_qc = Path(sys.argv[6])

rows = list(csv.DictReader(trials_tsv.open("r", encoding="utf-8"), delimiter="\t"))
if not rows:
    raise SystemExit("No fMRI trial rows found")

fc_r_list = [np.loadtxt(row["fc_pearson"], delimiter=",").astype(float) for row in rows]
fc_z_list = [np.loadtxt(row["fc_fisherz"], delimiter=",").astype(float) for row in rows]
fc_bbr_r_list = [np.loadtxt(row["fc_bbr_pearson"], delimiter=",").astype(float) for row in rows]
fc_bbr_z_list = [np.loadtxt(row["fc_bbr_fisherz"], delimiter=",").astype(float) for row in rows]
np.savetxt(out_fc_r, np.mean(fc_r_list, axis=0), delimiter=",", fmt="%.10f")
np.savetxt(out_fc_z, np.mean(fc_z_list, axis=0), delimiter=",", fmt="%.10f")
np.savetxt(out_fc_bbr_r, np.mean(fc_bbr_r_list, axis=0), delimiter=",", fmt="%.10f")
np.savetxt(out_fc_bbr_z, np.mean(fc_bbr_z_list, axis=0), delimiter=",", fmt="%.10f")

qc_rows = []
for row in rows:
    qc_path = Path(row["qc_json"])
    qc_data = {}
    if qc_path.exists():
      qc_data = json.loads(qc_path.read_text(encoding="utf-8"))
    qc_rows.append({"trial_name": row["trial_name"], "qc": qc_data})
out_qc.write_text(json.dumps(qc_rows, indent=2, ensure_ascii=False), encoding="utf-8")
PY

# 复制 SC 结果到 final 根目录和 dwi/sc 子目录。
for sc_path in \
  "$SC_SIFT2" \
  "$SC_SIFT2_INVNODEVOL" \
  "$SC_COUNT" \
  "$SC_COUNT_INVNODEVOL" \
  "$SC_SIFT2_RADIAL4" \
  "$SC_SIFT2_INVNODEVOL_RADIAL4" \
  "$SC_COUNT_RADIAL4" \
  "$SC_COUNT_INVNODEVOL_RADIAL4"; do
  cp -f "$sc_path" "${FINAL_DIR}/$(basename "$sc_path")"
  cp -f "$sc_path" "${FINAL_DIR}/dwi/sc/"
done

"$PYTHON_BIN" "${UTILS_DIR}/phase4_summary/step1/split_sc_matrices.py" \
  --labels-tsv "${LABELS_TSV}" \
  --count "${SC_COUNT}" \
  --count-invnodevol "${SC_COUNT_INVNODEVOL}" \
  --sift2 "${SC_SIFT2}" \
  --sift2-invnodevol "${SC_SIFT2_INVNODEVOL}" \
  --out-dir "${FINAL_DIR}/dwi/sc" \
  --subject-id "${SUBJECT_ID}"

# 记录当前 step 的核心输入和输出。
cat > "${STEP1_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
atlas_input	${ATLAS_NII}
labels_input	${LABELS_TSV}
sc_sift2_input	${SC_SIFT2}
sc_sift2_invnodevol_input	${SC_SIFT2_INVNODEVOL}
sc_count_input	${SC_COUNT}
sc_count_invnodevol_input	${SC_COUNT_INVNODEVOL}
sc_sift2_radial4_input	${SC_SIFT2_RADIAL4}
sc_sift2_invnodevol_radial4_input	${SC_SIFT2_INVNODEVOL_RADIAL4}
sc_count_radial4_input	${SC_COUNT_RADIAL4}
sc_count_invnodevol_radial4_input	${SC_COUNT_INVNODEVOL_RADIAL4}
sc_typed_manifest	${SC_TYPED_MANIFEST}
sc_typed_qc	${SC_TYPED_QC}
fmri_trials_tsv	${FMRI_TRIALS_TSV}
fmri_trials_qc_json	${FMRI_TRIALS_QC_JSON}
final_fc_pearson	${FINAL_DIR}/${SUBJECT_ID}_FC_pearson.csv
final_fc_fisherz	${FINAL_DIR}/${SUBJECT_ID}_FC_fisherz.csv
final_fc_bbr_pearson	${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_pearson.csv
final_fc_bbr_fisherz	${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_fisherz.csv
final_sc_sift2	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv
final_sc_sift2_invnodevol	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv
final_sc_count	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv
final_sc_count_invnodevol	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv
final_sc_sift2_radial4	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv
final_sc_sift2_invnodevol_radial4	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv
final_sc_count_radial4	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv
final_sc_count_invnodevol_radial4	${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv
final_sc_typed_manifest	${SC_TYPED_MANIFEST}
EOF
