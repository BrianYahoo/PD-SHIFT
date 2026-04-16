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
require_cmd mcflirt
require_cmd fslmaths
require_cmd "$PYTHON_BIN"

# 定义本 step 的输入输出路径。
FUNC_INPUT="${FMRI_DIR}/func_topup.nii.gz"
FUNC_MC="${FMRI_DIR}/func_mc.nii.gz"
FUNC_MEAN="${FMRI_DIR}/func_mean.nii.gz"
VIS_MOTION_DIR="${PHASE2_FMRI_DIR}/visualization/${FMRI_TRIAL_NAME}/motion"
MOTION_PNG="${VIS_MOTION_DIR}/motion_metrics.png"
MOTION_FD="${VIS_MOTION_DIR}/framewise_displacement.tsv"
MOTION_DONE="${VIS_MOTION_DIR}/motion_metrics.done"

# 回填 stepview 中的输入。
link_step_product_nifti 4 1 "motion_input" "$FUNC_INPUT"

# 如果运动校正和均值参考已经生成且 NIfTI 可读，则直接回填 stepview 并跳过。
if nifti_is_readable "$FUNC_MC" && nifti_is_readable "$FUNC_MEAN" && [[ -f "${FMRI_DIR}/func_mc.par" && -f "${MOTION_PNG}" && -f "${MOTION_DONE}" ]]; then
  link_step_product_nifti 4 1 "motion_corrected" "$FUNC_MC"
  link_step_product_nifti 4 2 "motion_reference" "$FUNC_MEAN"
  log "[phase2_fmri] Step4 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 如果旧的运动校正结果损坏，则删掉后重算。
if [[ -f "$FUNC_MC" && ! -L "$FUNC_MC" ]] && ! nifti_is_readable "$FUNC_MC"; then
  log "[phase2_fmri] Step4 detected unreadable motion output, rebuilding for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  rm -f "$FUNC_MC" "$FUNC_MEAN" "${FMRI_DIR}/func_mc.par" "${FMRI_DIR}/mcflirt.log" "${MOTION_PNG}" "${MOTION_FD}" "${MOTION_DONE}"
fi

# 如果刚体头动校正主结果还不存在，则执行 mcflirt。
if [[ ! -f "$FUNC_MC" || ! -f "${FMRI_DIR}/func_mc.par" ]]; then
  mcflirt -in "$FUNC_INPUT" -out "${FMRI_DIR}/func_mc" -plots -refvol 0 >"${FMRI_DIR}/mcflirt.log" 2>&1
fi

# 如果均值功能参考像还不存在，则重新计算。
if [[ ! -f "$FUNC_MEAN" ]]; then
  fslmaths "$FUNC_MC" -Tmean "$FUNC_MEAN"
fi

# 可视化头动参数与 FD，便于快速判断本 trial 的头动质量。
mkdir -p "${VIS_MOTION_DIR}"
"${PYTHON_BIN}" "${UTILS_DIR}/plot_motion_metrics.py" \
  --motion "${FMRI_DIR}/func_mc.par" \
  --fd-threshold "${FMRI_FD_THRESHOLD}" \
  --output-png "${MOTION_PNG}" \
  --output-fd "${MOTION_FD}"
touch "${MOTION_DONE}"

# 回填 stepview 中的输出。
link_step_product_nifti 4 1 "motion_corrected" "$FUNC_MC"
link_step_product_nifti 4 2 "motion_reference" "$FUNC_MEAN"
