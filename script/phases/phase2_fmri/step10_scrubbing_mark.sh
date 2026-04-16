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
FUNC_INPUT="${FMRI_DIR}/func_filter.nii.gz"
FD_TXT="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_FD_power.txt"
SCRUB_TXT="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_scrub_mask.txt"
SCRUB_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_scrub_qc.json"
TOXIC_NII="${FMRI_DIR}/toxic_frames.nii.gz"

# 回填 stepview 中的输入。
link_step_product_nifti 10 1 "scrubbing_input" "$FUNC_INPUT"

# 如果 scrubbing 标记结果已经存在，则直接回填 stepview 并跳过。
if [[ -f "$FD_TXT" && -f "$SCRUB_TXT" && -f "$TOXIC_NII" && -f "$SCRUB_QC" ]]; then
  link_step_product_nifti 10 2 "toxic_frames" "$TOXIC_NII"
  log "[phase2_fmri] Step10 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 计算 FD，并在开启时输出毒瘤帧标记；默认仅保留统计，不实际启用 scrubbing。
"$PYTHON_BIN" "${UTILS_DIR}/fmri_scrubbing.py" \
  --func "$FUNC_INPUT" \
  --motion "${FMRI_DIR}/func_mc.par" \
  --brain-mask "${FMRI_DIR}/gs_mask_func.nii.gz" \
  --enabled "$FMRI_ENABLE_SCRUBBING" \
  --fd-threshold "$FMRI_FD_THRESHOLD" \
  --scrub-before "$FMRI_SCRUB_BEFORE" \
  --scrub-after "$FMRI_SCRUB_AFTER" \
  --output-fd "$FD_TXT" \
  --output-toxic-mask "$SCRUB_TXT" \
  --output-toxic-nifti "$TOXIC_NII" \
  --output-qc "$SCRUB_QC"

# 回填 stepview 中的输出。
link_step_product_nifti 10 2 "toxic_frames" "$TOXIC_NII"
