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
FUNC_INPUT="${FMRI_DIR}/func_detrend.nii.gz"
FUNC_OUTPUT="${FMRI_DIR}/func_regress.nii.gz"
REGRESS_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_regress_qc.json"

# 回填 stepview 中的输入。
link_step_product_nifti 8 1 "regress_input" "$FUNC_INPUT"

# 如果协变量回归结果已经存在，则直接回填 stepview 并跳过。
if [[ -f "$FUNC_OUTPUT" && -f "$REGRESS_QC" ]]; then
  link_step_product_nifti 8 2 "regress_output" "$FUNC_OUTPUT"
  log "[phase2_fmri] Step8 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 对功能像执行 GS/WM/CSF/HM 协变量回归。
"$PYTHON_BIN" "${UTILS_DIR}/fmri_regress_covariates.py" \
  --func "$FUNC_INPUT" \
  --motion "${FMRI_DIR}/func_mc.par" \
  --brain-mask "${FMRI_DIR}/gs_mask_func.nii.gz" \
  --wm-mask "${FMRI_DIR}/wm_mask_func.nii.gz" \
  --csf-mask "${FMRI_DIR}/csf_mask_func.nii.gz" \
  --gs-mask "${FMRI_DIR}/gs_mask_func.nii.gz" \
  --regress-gs "$FMRI_REGRESS_GS" \
  --regress-wm "$FMRI_REGRESS_WM" \
  --regress-csf "$FMRI_REGRESS_CSF" \
  --regress-hm "$FMRI_REGRESS_HM" \
  --hm-model "$FMRI_HM_MODEL" \
  --output-func "$FUNC_OUTPUT" \
  --output-qc "$REGRESS_QC"

# 回填 stepview 中的输出。
link_step_product_nifti 8 2 "regress_output" "$FUNC_OUTPUT"
