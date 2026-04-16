#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config
# 建立当前 trial 的输入输出目录。
setup_fmri_trial_context "${FMRI_TRIAL_NAME:-}"
# 加载 conda、FSL、FreeSurfer、ANTs 等工具环境。
setup_tools_env

# 检查当前 step 依赖的命令是否存在。
require_cmd "$PYTHON_BIN"

# 定义本 step 的输入输出路径。
LABELS_TSV="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"
FUNC_FILTER="${FMRI_DIR}/func_filter.nii.gz"
FC_R="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_FC_pearson.csv"
FC_Z="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_FC_fisherz.csv"
FC_TS="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_FC_timeseries.tsv"
FC_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_FC_qc.json"
REGRESS_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_regress_qc.json"
DETREND_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_detrend_qc.json"
FILTER_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_filter_qc.json"
SCRUB_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_scrub_qc.json"
STEPWISE_DONE="${FMRI_DIR}/stepresult/stepwise.done"

# 回填 stepview 中的输入和 atlas。
link_step_product_nifti 11 1 "extract_signal_input" "$FUNC_FILTER"
link_step_product_nifti 11 2 "extract_signal_atlas" "${FMRI_DIR}/atlas_in_func.nii.gz"

# 如果最终时序、FC，以及 Step11 内部的逐步诊断都已存在，则直接跳过。
if [[ -f "$FC_R" && -f "$FC_Z" && -f "$FC_TS" && -f "$FC_QC" && -f "${FMRI_DIR}/manifest.tsv" && -f "${STEPWISE_DONE}" ]]; then
  log "[phase2_fmri] Step11 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 使用 NiftiLabelsMasker 从最终滤波后的 4D 数据中提取 ROI 时序，并计算 FC 矩阵。
"$PYTHON_BIN" "${UTILS_DIR}/phase2_fmri/step11/fmri_extract_signal.py" \
  --func "$FUNC_FILTER" \
  --atlas "${FMRI_DIR}/atlas_in_func.nii.gz" \
  --labels "$LABELS_TSV" \
  --output-matrix "$FC_R" \
  --output-z "$FC_Z" \
  --output-timeseries "$FC_TS" \
  --output-qc "$FC_QC" \
  --scrub-qc "$SCRUB_QC" \
  --regress-qc "$REGRESS_QC" \
  --detrend-qc "$DETREND_QC" \
  --filter-qc "$FILTER_QC"

# 记录当前 trial 最终使用的输入和输出文件位置。
cat > "${FMRI_DIR}/manifest.tsv" <<EOF
key	value
subject_id	${SUBJECT_ID}
trial_name	${FMRI_TRIAL_NAME}
func_input	${FMRI_FUNC_INPUT}
func_filter	${FUNC_FILTER}
atlas_in_func	${FMRI_DIR}/atlas_in_func.nii.gz
fc_pearson	${FC_R}
fc_fisherz	${FC_Z}
timeseries	${FC_TS}
qc_json	${FC_QC}
EOF

# 在 Extract Signal 内部追加逐步诊断子步骤，但不暴露为外层独立 step。
bash "${STEP_DIR}/step12_stepwise_diagnostics.sh"
