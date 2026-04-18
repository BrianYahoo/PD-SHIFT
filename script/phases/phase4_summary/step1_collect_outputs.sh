#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

load_config
setup_tools_env

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

ATLAS_FINAL_DIR="${FINAL_DIR}/dwi/atlas"
DWI_SC_DIR="${FINAL_DIR}/dwi/sc"
DWI_SC_WHOLE_DIR="${DWI_SC_DIR}/whole"
DWI_SC_CORTEX_DIR="${DWI_SC_DIR}/cortex"
DWI_SC_SUBCORTEX_DIR="${DWI_SC_DIR}/subcortex"
DWI_SC_SUB2CORTEX_DIR="${DWI_SC_DIR}/sub2cortex"
FUNC_FC_DIR="${FINAL_DIR}/func/fc"
FUNC_TIMESERIES_DIR="${FINAL_DIR}/func/timeseries"
FUNC_AVG_STEP5_DIR="${FUNC_FC_DIR}/average/step5"
FUNC_AVG_STEP11_DIR="${FUNC_FC_DIR}/average/step11"
ATLAS_FINAL_PATH="${ATLAS_FINAL_DIR}/$(basename "${ATLAS_NII}")"
LABELS_FINAL_PATH="${FINAL_DIR}/${SUBJECT_ID}_labels.tsv"
FC_AVG_STEP5_R="${FUNC_AVG_STEP5_DIR}/${SUBJECT_ID}_FC_bbr_pearson.csv"
FC_AVG_STEP5_Z="${FUNC_AVG_STEP5_DIR}/${SUBJECT_ID}_FC_bbr_fisherz.csv"
FC_AVG_STEP11_R="${FUNC_AVG_STEP11_DIR}/${SUBJECT_ID}_FC_pearson.csv"
FC_AVG_STEP11_Z="${FUNC_AVG_STEP11_DIR}/${SUBJECT_ID}_FC_fisherz.csv"
SC_TYPED_MANIFEST="${DWI_SC_DIR}/${SUBJECT_ID}_DTI_connectome_typed_manifest.tsv"
SC_TYPED_QC="${DWI_SC_DIR}/${SUBJECT_ID}_DTI_connectome_typed_qc.json"
FMRI_TRIALS_TSV="${FINAL_DIR}/func/fmri_trials.tsv"
FMRI_TRIALS_QC_JSON="${REPORTS_DIR}/fmri_trials_qc.json"
STEP1_MANIFEST="${REPORTS_DIR}/step1_collect_outputs_manifest.tsv"
LAYOUT_VERSION="phase4_summary_v2"

require_sc_inputs() {
  local sc_path=""
  for sc_path in \
    "${SC_SIFT2}" \
    "${SC_SIFT2_INVNODEVOL}" \
    "${SC_COUNT}" \
    "${SC_COUNT_INVNODEVOL}" \
    "${SC_SIFT2_RADIAL4}" \
    "${SC_SIFT2_INVNODEVOL_RADIAL4}" \
    "${SC_COUNT_RADIAL4}" \
    "${SC_COUNT_INVNODEVOL_RADIAL4}"; do
    [[ -f "${sc_path}" ]] || die "Missing SC output: ${sc_path}"
  done
}

copy_trial_step_outputs() {
  local trial_name="$1"
  local trial_fmri_dir="${FMRI_ROOT_DIR}/${trial_name}"
  local step_no="$2"
  local step_name="$3"
  local src_prefix="${trial_fmri_dir}/stepresult/step${step_no}_${step_name}"
  local fc_step_dir="${FUNC_FC_DIR}/${trial_name}/step${step_no}"
  local ts_step_dir="${FUNC_TIMESERIES_DIR}/${trial_name}/step${step_no}"

  mkdir -p "${fc_step_dir}" "${ts_step_dir}"
  [[ -f "${src_prefix}_fc_pearson.csv" ]] || die "Missing step${step_no} FC for ${trial_name}"
  [[ -f "${src_prefix}_fc_fisherz.csv" ]] || die "Missing step${step_no} FC z for ${trial_name}"
  [[ -f "${src_prefix}_timeseries.tsv" ]] || die "Missing step${step_no} timeseries for ${trial_name}"
  [[ -f "${src_prefix}_qc.json" ]] || die "Missing step${step_no} QC for ${trial_name}"

  cp -f "${src_prefix}_fc_pearson.csv" "${fc_step_dir}/step${step_no}_${step_name}_fc_pearson.csv"
  cp -f "${src_prefix}_fc_fisherz.csv" "${fc_step_dir}/step${step_no}_${step_name}_fc_fisherz.csv"
  cp -f "${src_prefix}_qc.json" "${fc_step_dir}/step${step_no}_${step_name}_qc.json"
  cp -f "${src_prefix}_timeseries.tsv" "${ts_step_dir}/step${step_no}_${step_name}_timeseries.tsv"
}

check_trial_outputs_ready() {
  local trial_name="$1"
  local step_no=""
  local step_name=""
  local fc_step_dir=""
  local ts_step_dir=""

  for step_spec in \
    "5:bbr" \
    "6:smooth" \
    "7:detrend" \
    "8:regress" \
    "9:filter" \
    "10:scrubbing"; do
    step_no="${step_spec%%:*}"
    step_name="${step_spec##*:}"
    fc_step_dir="${FUNC_FC_DIR}/${trial_name}/step${step_no}"
    ts_step_dir="${FUNC_TIMESERIES_DIR}/${trial_name}/step${step_no}"
    [[ -f "${fc_step_dir}/step${step_no}_${step_name}_fc_pearson.csv" ]] || return 1
    [[ -f "${fc_step_dir}/step${step_no}_${step_name}_fc_fisherz.csv" ]] || return 1
    [[ -f "${fc_step_dir}/step${step_no}_${step_name}_qc.json" ]] || return 1
    [[ -f "${ts_step_dir}/step${step_no}_${step_name}_timeseries.tsv" ]] || return 1
  done

  [[ -f "${FUNC_FC_DIR}/${trial_name}/step10/${SUBJECT_ID}_${trial_name}_scrub_mask.txt" ]] || return 1
  [[ -f "${FUNC_FC_DIR}/${trial_name}/step10/${SUBJECT_ID}_${trial_name}_scrub_qc.json" ]] || return 1
  [[ -f "${FUNC_FC_DIR}/${trial_name}/step11/step11_fc_pearson.csv" ]] || return 1
  [[ -f "${FUNC_FC_DIR}/${trial_name}/step11/step11_fc_fisherz.csv" ]] || return 1
  [[ -f "${FUNC_FC_DIR}/${trial_name}/step11/step11_fc_qc.json" ]] || return 1
  [[ -f "${FUNC_FC_DIR}/${trial_name}/step11/${SUBJECT_ID}_${trial_name}_FD_power.txt" ]] || return 1
  [[ -f "${FUNC_TIMESERIES_DIR}/${trial_name}/step11/step11_fc_timeseries.tsv" ]] || return 1
}

step1_ready() {
  local trial_name=""
  [[ -f "${STEP1_MANIFEST}" ]] || return 1
  [[ "$(read_manifest_value "${STEP1_MANIFEST}" "layout_version")" == "${LAYOUT_VERSION}" ]] || return 1
  [[ -f "${ATLAS_FINAL_PATH}" ]] || return 1
  [[ -f "${LABELS_FINAL_PATH}" ]] || return 1
  [[ -f "${SC_TYPED_MANIFEST}" ]] || return 1
  [[ -f "${SC_TYPED_QC}" ]] || return 1
  [[ -f "${FMRI_TRIALS_TSV}" ]] || return 1
  [[ -f "${FMRI_TRIALS_QC_JSON}" ]] || return 1

  for sc_path in \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv" \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv" \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv" \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv" \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv" \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv" \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv" \
    "${DWI_SC_WHOLE_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv" \
    "${DWI_SC_CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_cortical.csv" \
    "${DWI_SC_CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_cortical.csv" \
    "${DWI_SC_CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_count_cortical.csv" \
    "${DWI_SC_CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_cortical.csv" \
    "${DWI_SC_SUBCORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_subcortical.csv" \
    "${DWI_SC_SUBCORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_subcortical.csv" \
    "${DWI_SC_SUBCORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_count_subcortical.csv" \
    "${DWI_SC_SUBCORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_subcortical.csv" \
    "${DWI_SC_SUB2CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_subcortex_cortex.csv" \
    "${DWI_SC_SUB2CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_subcortex_cortex.csv" \
    "${DWI_SC_SUB2CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_count_subcortex_cortex.csv" \
    "${DWI_SC_SUB2CORTEX_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_subcortex_cortex.csv"; do
    [[ -f "${sc_path}" ]] || return 1
  done

  if (( ${#FMRI_TRIALS[@]} > 0 )); then
    [[ -f "${FC_AVG_STEP5_R}" ]] || return 1
    [[ -f "${FC_AVG_STEP5_Z}" ]] || return 1
    [[ -f "${FC_AVG_STEP11_R}" ]] || return 1
    [[ -f "${FC_AVG_STEP11_Z}" ]] || return 1
    for trial_name in "${FMRI_TRIALS[@]}"; do
      check_trial_outputs_ready "${trial_name}" || return 1
    done
  fi

  return 0
}

[[ -f "${ATLAS_NII}" ]] || die "Missing atlas output"
[[ -f "${LABELS_TSV}" ]] || die "Missing labels output"
require_sc_inputs

mapfile -t FMRI_TRIALS < <(list_fmri_trial_names)
HAS_PROCESSABLE_FMRI=0
if (( ${#FMRI_TRIALS[@]} > 0 )); then
  HAS_PROCESSABLE_FMRI=1
fi

if step1_ready; then
  log "[phase4_summary] Step1 already done for ${SUBJECT_ID}"
  exit 0
fi

mkdir -p \
  "${ATLAS_FINAL_DIR}" \
  "${DWI_SC_WHOLE_DIR}" \
  "${DWI_SC_CORTEX_DIR}" \
  "${DWI_SC_SUBCORTEX_DIR}" \
  "${DWI_SC_SUB2CORTEX_DIR}" \
  "${FUNC_FC_DIR}" \
  "${FUNC_TIMESERIES_DIR}" \
  "${FUNC_AVG_STEP5_DIR}" \
  "${FUNC_AVG_STEP11_DIR}" \
  "${REPORTS_DIR}"

cp -f "${ATLAS_NII}" "${ATLAS_FINAL_PATH}"
cp -f "${LABELS_TSV}" "${LABELS_FINAL_PATH}"

cp -f "${SC_SIFT2_RADIAL4}" "${DWI_SC_WHOLE_DIR}/"
cp -f "${SC_SIFT2_INVNODEVOL_RADIAL4}" "${DWI_SC_WHOLE_DIR}/"
cp -f "${SC_COUNT_RADIAL4}" "${DWI_SC_WHOLE_DIR}/"
cp -f "${SC_COUNT_INVNODEVOL_RADIAL4}" "${DWI_SC_WHOLE_DIR}/"

"${PYTHON_BIN}" "${UTILS_DIR}/phase4_summary/step1/split_sc_matrices.py" \
  --labels-tsv "${LABELS_TSV}" \
  --count "${SC_COUNT}" \
  --count-invnodevol "${SC_COUNT_INVNODEVOL}" \
  --sift2 "${SC_SIFT2}" \
  --sift2-invnodevol "${SC_SIFT2_INVNODEVOL}" \
  --out-dir "${DWI_SC_DIR}" \
  --subject-id "${SUBJECT_ID}"

cat > "${FMRI_TRIALS_TSV}" <<EOF
trial_name	step5_fc_pearson	step5_fc_fisherz	step5_timeseries	step10_fc_pearson	step10_fc_fisherz	step10_timeseries	step11_fc_pearson	step11_fc_fisherz	step11_timeseries	step11_qc	fd_txt	scrub_txt
EOF

if [[ "${HAS_PROCESSABLE_FMRI}" == "1" ]]; then
  for trial_name in "${FMRI_TRIALS[@]}"; do
    trial_fmri_dir="${FMRI_ROOT_DIR}/${trial_name}"
    trial_step10_fc_dir="${FUNC_FC_DIR}/${trial_name}/step10"
    trial_step11_fc_dir="${FUNC_FC_DIR}/${trial_name}/step11"
    trial_step11_ts_dir="${FUNC_TIMESERIES_DIR}/${trial_name}/step11"
    trial_fc_r="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_pearson.csv"
    trial_fc_z="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_fisherz.csv"
    trial_fc_ts="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_timeseries.tsv"
    trial_fc_qc="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FC_qc.json"
    trial_fd_txt="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_FD_power.txt"
    trial_scrub_txt="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_scrub_mask.txt"
    trial_scrub_qc="${trial_fmri_dir}/${SUBJECT_ID}_${trial_name}_scrub_qc.json"

    for step_spec in \
      "5:bbr" \
      "6:smooth" \
      "7:detrend" \
      "8:regress" \
      "9:filter" \
      "10:scrubbing"; do
      copy_trial_step_outputs "${trial_name}" "${step_spec%%:*}" "${step_spec##*:}"
    done

    [[ -f "${trial_fc_r}" ]] || die "Missing FC output for ${trial_name}"
    [[ -f "${trial_fc_z}" ]] || die "Missing FC z output for ${trial_name}"
    [[ -f "${trial_fc_ts}" ]] || die "Missing FC timeseries for ${trial_name}"
    [[ -f "${trial_fc_qc}" ]] || die "Missing FC QC for ${trial_name}"
    [[ -f "${trial_fd_txt}" ]] || die "Missing FD output for ${trial_name}"
    [[ -f "${trial_scrub_txt}" ]] || die "Missing scrub mask for ${trial_name}"
    [[ -f "${trial_scrub_qc}" ]] || die "Missing scrub QC for ${trial_name}"

    mkdir -p "${trial_step10_fc_dir}" "${trial_step11_fc_dir}" "${trial_step11_ts_dir}"
    cp -f "${trial_scrub_txt}" "${trial_step10_fc_dir}/"
    cp -f "${trial_scrub_qc}" "${trial_step10_fc_dir}/"
    cp -f "${trial_fc_r}" "${trial_step11_fc_dir}/step11_fc_pearson.csv"
    cp -f "${trial_fc_z}" "${trial_step11_fc_dir}/step11_fc_fisherz.csv"
    cp -f "${trial_fc_qc}" "${trial_step11_fc_dir}/step11_fc_qc.json"
    cp -f "${trial_fd_txt}" "${trial_step11_fc_dir}/"
    cp -f "${trial_fc_ts}" "${trial_step11_ts_dir}/step11_fc_timeseries.tsv"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${trial_name}" \
      "${FUNC_FC_DIR}/${trial_name}/step5/step5_bbr_fc_pearson.csv" \
      "${FUNC_FC_DIR}/${trial_name}/step5/step5_bbr_fc_fisherz.csv" \
      "${FUNC_TIMESERIES_DIR}/${trial_name}/step5/step5_bbr_timeseries.tsv" \
      "${FUNC_FC_DIR}/${trial_name}/step10/step10_scrubbing_fc_pearson.csv" \
      "${FUNC_FC_DIR}/${trial_name}/step10/step10_scrubbing_fc_fisherz.csv" \
      "${FUNC_TIMESERIES_DIR}/${trial_name}/step10/step10_scrubbing_timeseries.tsv" \
      "${FUNC_FC_DIR}/${trial_name}/step11/step11_fc_pearson.csv" \
      "${FUNC_FC_DIR}/${trial_name}/step11/step11_fc_fisherz.csv" \
      "${FUNC_TIMESERIES_DIR}/${trial_name}/step11/step11_fc_timeseries.tsv" \
      "${FUNC_FC_DIR}/${trial_name}/step11/step11_fc_qc.json" \
      "${FUNC_FC_DIR}/${trial_name}/step11/$(basename "${trial_fd_txt}")" \
      "${FUNC_FC_DIR}/${trial_name}/step10/$(basename "${trial_scrub_txt}")" >> "${FMRI_TRIALS_TSV}"
  done

  "${PYTHON_BIN}" - "${FMRI_TRIALS_TSV}" "${FC_AVG_STEP11_R}" "${FC_AVG_STEP11_Z}" "${FC_AVG_STEP5_R}" "${FC_AVG_STEP5_Z}" "${FMRI_TRIALS_QC_JSON}" <<'PY'
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

fc_r_list = [np.loadtxt(row["step11_fc_pearson"], delimiter=",").astype(float) for row in rows]
fc_z_list = [np.loadtxt(row["step11_fc_fisherz"], delimiter=",").astype(float) for row in rows]
fc_bbr_r_list = [np.loadtxt(row["step5_fc_pearson"], delimiter=",").astype(float) for row in rows]
fc_bbr_z_list = [np.loadtxt(row["step5_fc_fisherz"], delimiter=",").astype(float) for row in rows]
np.savetxt(out_fc_r, np.mean(fc_r_list, axis=0), delimiter=",", fmt="%.10f")
np.savetxt(out_fc_z, np.mean(fc_z_list, axis=0), delimiter=",", fmt="%.10f")
np.savetxt(out_fc_bbr_r, np.mean(fc_bbr_r_list, axis=0), delimiter=",", fmt="%.10f")
np.savetxt(out_fc_bbr_z, np.mean(fc_bbr_z_list, axis=0), delimiter=",", fmt="%.10f")

qc_rows = []
for row in rows:
    qc_path = Path(row["step11_qc"])
    qc_data = {}
    if qc_path.exists():
        qc_data = json.loads(qc_path.read_text(encoding="utf-8"))
    qc_rows.append({"trial_name": row["trial_name"], "qc": qc_data})
out_qc.write_text(json.dumps(qc_rows, indent=2, ensure_ascii=False), encoding="utf-8")
PY
else
  printf '[]\n' > "${FMRI_TRIALS_QC_JSON}"
fi

cat > "${STEP1_MANIFEST}" <<EOF
key	value
layout_version	${LAYOUT_VERSION}
subject_id	${SUBJECT_ID}
atlas_input	${ATLAS_NII}
atlas_output	${ATLAS_FINAL_PATH}
labels_input	${LABELS_TSV}
labels_output	${LABELS_FINAL_PATH}
sc_sift2_input	${SC_SIFT2}
sc_sift2_invnodevol_input	${SC_SIFT2_INVNODEVOL}
sc_count_input	${SC_COUNT}
sc_count_invnodevol_input	${SC_COUNT_INVNODEVOL}
sc_sift2_radial4_input	${SC_SIFT2_RADIAL4}
sc_sift2_invnodevol_radial4_input	${SC_SIFT2_INVNODEVOL_RADIAL4}
sc_count_radial4_input	${SC_COUNT_RADIAL4}
sc_count_invnodevol_radial4_input	${SC_COUNT_INVNODEVOL_RADIAL4}
sc_whole_dir	${DWI_SC_WHOLE_DIR}
sc_cortex_dir	${DWI_SC_CORTEX_DIR}
sc_subcortex_dir	${DWI_SC_SUBCORTEX_DIR}
sc_sub2cortex_dir	${DWI_SC_SUB2CORTEX_DIR}
sc_typed_manifest	${SC_TYPED_MANIFEST}
sc_typed_qc	${SC_TYPED_QC}
fmri_trials_tsv	${FMRI_TRIALS_TSV}
fmri_trials_qc_json	${FMRI_TRIALS_QC_JSON}
final_fc_step5_pearson	${FC_AVG_STEP5_R}
final_fc_step5_fisherz	${FC_AVG_STEP5_Z}
final_fc_step11_pearson	${FC_AVG_STEP11_R}
final_fc_step11_fisherz	${FC_AVG_STEP11_Z}
EOF
