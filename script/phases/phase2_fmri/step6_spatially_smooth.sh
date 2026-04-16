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
require_cmd fslmaths

# 定义本 step 的输入输出路径。
FUNC_INPUT="${FMRI_DIR}/func_mc.nii.gz"
FUNC_OUTPUT="${FMRI_DIR}/func_smooth.nii.gz"

# 回填 stepview 中的输入。
link_step_product_nifti 6 1 "smooth_input" "$FUNC_INPUT"

# 如果平滑结果已经存在，则直接回填 stepview 并跳过。
if [[ -f "$FUNC_OUTPUT" ]]; then
  link_step_product_nifti 6 2 "smooth_output" "$FUNC_OUTPUT"
  log "[phase2_fmri] Step6 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 默认不启用空间平滑；当 FWHM 为 0 时直接沿用原始输入。
if [[ "$FMRI_SMOOTH_FWHM_MM" == "0" || "$FMRI_SMOOTH_FWHM_MM" == "0.0" ]]; then
  ln -sfn "$FUNC_INPUT" "$FUNC_OUTPUT"
else
  SIGMA_MM="$("$PYTHON_BIN" - "$FMRI_SMOOTH_FWHM_MM" <<'PY'
import sys
fwhm = float(sys.argv[1])
print(f"{fwhm / 2.354820045:.8f}")
PY
)"
  fslmaths "$FUNC_INPUT" -s "$SIGMA_MM" "$FUNC_OUTPUT"
fi

# 回填 stepview 中的输出。
link_step_product_nifti 6 2 "smooth_output" "$FUNC_OUTPUT"
