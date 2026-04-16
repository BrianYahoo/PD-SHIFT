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
require_cmd fslroi
require_cmd fslval

# 定义本 step 的输入输出路径。
FUNC_INPUT="${FMRI_FUNC_INPUT}"
FUNC_TRIM="${FMRI_DIR}/func_trim.nii.gz"

# 第一步开始前先清理旧的 stepview 链接，避免新旧命名混在一起。
find "${FMRI_STEPS_TRIAL_DIR}" -maxdepth 1 -type l -name 'step*.nii.gz' -delete 2>/dev/null || true

# 检查原始功能像输入是否存在。
[[ -f "$FUNC_INPUT" ]] || die "Missing func input"

# 在 stepview 中保留原始输入和去前导后的结果。
link_step_product_nifti 1 1 "raw_input" "$FUNC_INPUT"

# 如果已经完成去前导时间点且结果可读，则直接回填 stepview 并跳过。
if nifti_is_readable "$FUNC_TRIM"; then
  link_step_product_nifti 1 2 "remove_start_images" "$FUNC_TRIM"
  log "[phase2_fmri] Step1 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 如果旧的 trim 结果损坏，则先删掉后重建。
if [[ -f "$FUNC_TRIM" ]]; then
  log "[phase2_fmri] Step1 detected unreadable output, rebuilding for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  rm -f "$FUNC_TRIM"
fi

# 读取总时间点数，用于决定需要丢弃多少前导时间点。
TOTAL_VOL="$(fslval "$FUNC_INPUT" dim4 | tr -d ' ')"
KEEP_VOL=$(( TOTAL_VOL - DUMMY_VOLUMES ))

# 如果当前时间点太少，则退回为不丢弃任何时间点。
if (( KEEP_VOL < 20 )); then
  KEEP_VOL="$TOTAL_VOL"
  REMOVE_VOL=0
else
  REMOVE_VOL="$DUMMY_VOLUMES"
fi

# 执行去前导时间点。
fslroi "$FUNC_INPUT" "$FUNC_TRIM" "$REMOVE_VOL" "$KEEP_VOL"

# 回填 stepview。
link_step_product_nifti 1 2 "remove_start_images" "$FUNC_TRIM"
