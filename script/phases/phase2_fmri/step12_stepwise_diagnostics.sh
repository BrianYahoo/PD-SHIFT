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

# 定义 step5-10 逐步诊断需要的输入与输出目录。
LABELS_TSV="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"
STEPRESULT_DIR="${FMRI_DIR}/stepresult"
STEPSIGNAL_DIR="${FMRI_STEPS_TRIAL_DIR}/stepsignal"
STEPFC_DIR="${FMRI_STEPS_TRIAL_DIR}/stepfc"
STEPRESULT_DONE="${STEPRESULT_DIR}/stepwise.done"

# 定义 step5-10 对应的实际 4D 数据。
STEP5_FUNC="${FMRI_DIR}/func_mc.nii.gz"
STEP6_FUNC="${FMRI_DIR}/func_smooth.nii.gz"
if ! nifti_is_readable "${STEP6_FUNC}"; then
  STEP6_FUNC="${STEP5_FUNC}"
fi
STEP7_FUNC="${FMRI_DIR}/func_detrend.nii.gz"
STEP8_FUNC="${FMRI_DIR}/func_regress.nii.gz"
STEP9_FUNC="${FMRI_DIR}/func_filter.nii.gz"
STEP10_FUNC="${FMRI_DIR}/func_filter.nii.gz"
STEP10_SCRUB_MASK="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_scrub_mask.txt"

mkdir -p "${STEPRESULT_DIR}" "${STEPSIGNAL_DIR}" "${STEPFC_DIR}"

# 输出当前子步骤的开始日志。
log "[phase2_fmri] Step11 substep stepwise diagnostics for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"

# 如果逐步诊断的核心结果与图片都已齐全，则直接跳过。
if [[ -f "${STEPRESULT_DONE}" \
  && -f "${STEPRESULT_DIR}/step5_bbr_timeseries.tsv" \
  && -f "${STEPRESULT_DIR}/step10_scrubbing_fc_pearson.csv" \
  && -f "${STEPSIGNAL_DIR}/step5_bbr_signal.png" \
  && -f "${STEPSIGNAL_DIR}/step10_scrubbing_signal.png" \
  && -f "${STEPFC_DIR}/step5_bbr_fc.png" \
  && -f "${STEPFC_DIR}/step10_scrubbing_fc.png" \
  && -f "${STEPFC_DIR}/overall.png" ]]; then
  log "[phase2_fmri] Step11 substep stepwise diagnostics already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 对 step5-10 的数据分别做 ROI 时序提取、FC 计算与可视化。
"${PYTHON_BIN}" "${UTILS_DIR}/phase2_fmri/step12/fmri_stepwise_diagnostics.py" \
  --atlas "${FMRI_DIR}/atlas_in_func.nii.gz" \
  --labels "${LABELS_TSV}" \
  --result-dir "${STEPRESULT_DIR}" \
  --signal-dir "${STEPSIGNAL_DIR}" \
  --fc-dir "${STEPFC_DIR}" \
  --sample-rois "1,11,22,33,44,55,66,88" \
  --sample-length 200 \
  --step-spec "5|bbr|${STEP5_FUNC}|" \
  --step-spec "6|smooth|${STEP6_FUNC}|" \
  --step-spec "7|detrend|${STEP7_FUNC}|" \
  --step-spec "8|regress|${STEP8_FUNC}|" \
  --step-spec "9|filter|${STEP9_FUNC}|" \
  --step-spec "10|scrubbing|${STEP10_FUNC}|${STEP10_SCRUB_MASK}"

touch "${STEPRESULT_DONE}"
log "[phase2_fmri] Step11 substep stepwise diagnostics done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
