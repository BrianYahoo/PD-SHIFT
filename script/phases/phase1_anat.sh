#!/usr/bin/env bash
set -euo pipefail

# 计算当前入口脚本所在目录，后面用它去定位 step 子脚本。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common.sh"

PHASE1_STEPS=(
  "phase1_anat/step1_brain_extract.sh"
  "phase1_anat/step2_surfer_recon.sh"
  "phase1_anat/step3_subcortical_syn.sh"
  "phase1_anat/step4_warpdrive_review.sh"
  "phase1_anat/step5_save_inverse_warp.sh"
  "phase1_anat/step6_distal_inverse_fusion.sh"
)

# 依次执行 phase1_anat 的全部 step。
for step_script in "${PHASE1_STEPS[@]}"; do
  bash "${SCRIPT_DIR}/phases/${step_script}"
done

# 在入口层输出 phase1_anat 完成日志。
load_config
log "[phase1_anat] Done: ${SUBJECT_ID}"
