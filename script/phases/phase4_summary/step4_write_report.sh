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

# 定义生成 summary 报告需要引用的关键文件。
ATLAS_NII="${FINAL_DIR}/dwi/atlas/${SUBJECT_ID}_desc-custom_dseg.nii.gz"
FC_R="${FINAL_DIR}/func/fc/average/step11/${SUBJECT_ID}_FC_pearson.csv"
FC_Z="${FINAL_DIR}/func/fc/average/step11/${SUBJECT_ID}_FC_fisherz.csv"
FMRI_TRIALS_TSV="${FINAL_DIR}/func/fmri_trials.tsv"
FMRI_TRIALS_QC_JSON="${REPORTS_DIR}/fmri_trials_qc.json"
SC_SIFT2="${FINAL_DIR}/dwi/sc/whole/${SUBJECT_ID}_DTI_connectome_sift2.csv"
SC_SIFT2_INVNODEVOL="${FINAL_DIR}/dwi/sc/whole/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv"
SC_COUNT="${FINAL_DIR}/dwi/sc/whole/${SUBJECT_ID}_DTI_connectome_count.csv"
SC_COUNT_INVNODEVOL="${FINAL_DIR}/dwi/sc/whole/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv"
TVP_MODEL_DIR="${FINAL_DIR}/dwi/modeling/tvp"
SUMMARY_MD="${REPORTS_DIR}/phase4_summary.md"
SUMMARY_MANIFEST="${REPORTS_DIR}/manifest.tsv"

# 如果报告和 manifest 已存在，则直接跳过。
if [[ -f "${SUMMARY_MD}" && -f "${SUMMARY_MANIFEST}" ]]; then
  log "[phase4_summary] Step4 already done for ${SUBJECT_ID}"
  exit 0
fi

FC_R_DISPLAY="N/A"
FC_Z_DISPLAY="N/A"
if [[ -f "${FC_R}" ]]; then
  FC_R_DISPLAY="${FC_R}"
fi
if [[ -f "${FC_Z}" ]]; then
  FC_Z_DISPLAY="${FC_Z}"
fi

# 生成简明的 markdown 汇总报告。
cat > "${SUMMARY_MD}" <<EOF
# Pipeline Summary (${SUBJECT_ID})

## Final Files

- Atlas: ${ATLAS_NII}
- Labels: ${FINAL_DIR}/${SUBJECT_ID}_labels.tsv
- FC Pearson: ${FC_R_DISPLAY}
- FC Fisher-z: ${FC_Z_DISPLAY}
- fMRI Trial Table: ${FMRI_TRIALS_TSV}
- SC SIFT2: ${SC_SIFT2}
- SC SIFT2 InvNodeVol: ${SC_SIFT2_INVNODEVOL}
- SC Count: ${SC_COUNT}
- SC Count InvNodeVol: ${SC_COUNT_INVNODEVOL}
- TVP Modeling Inputs: ${TVP_MODEL_DIR}

## Reports

- fMRI Trial QC: ${FMRI_TRIALS_QC_JSON}
- Comparison: ${COMPARE_DIR}/summary.md
EOF

# 生成 summary 模块自己的 manifest。
cat > "${SUMMARY_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
final_dir	${FINAL_DIR}
atlas	${ATLAS_NII}
fc_pearson	${FC_R_DISPLAY}
fc_fisherz	${FC_Z_DISPLAY}
fmri_trials	${FMRI_TRIALS_TSV}
sc_sift2	${SC_SIFT2}
sc_sift2_invnodevol	${SC_SIFT2_INVNODEVOL}
sc_count	${SC_COUNT}
sc_count_invnodevol	${SC_COUNT_INVNODEVOL}
tvp_model_dir	${TVP_MODEL_DIR}
comparison_dir	${COMPARE_DIR}
summary_report	${SUMMARY_MD}
EOF
