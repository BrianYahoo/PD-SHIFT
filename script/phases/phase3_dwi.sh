#!/usr/bin/env bash
set -euo pipefail

# 计算当前入口脚本所在目录，后面用它去定位 step 子脚本。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common.sh"

# 先加载配置，保证入口层也能输出统一的 subject 级日志。
load_config

# 按顺序定义 phase3_dwi 需要执行的 step 子脚本与主日志描述。
PHASE3_STEPS=(
  "phase3_dwi/step1_import_raw.sh"
  "phase3_dwi/step2_preprocess.sh"
  "phase3_dwi/step3_fod.sh"
  "phase3_dwi/step4_registration.sh"
  "phase3_dwi/step5_tractography.sh"
  "phase3_dwi/step6_connectome.sh"
)
PHASE3_STEP_MESSAGES=(
  "Step1 import raw"
  "Step2 preprocess"
  "Step3 fod"
  "Step4 registration"
  "Step5 tractography"
  "Step6 connectome"
)

# 依次执行每个 phase3_dwi step，并在主日志中明确当前推进到哪一步。
for idx in "${!PHASE3_STEPS[@]}"; do
  log "[phase3_dwi] ${PHASE3_STEP_MESSAGES[$idx]} for ${SUBJECT_ID}"
  bash "${SCRIPT_DIR}/phases/${PHASE3_STEPS[$idx]}"
done

# 在入口层输出 phase3_dwi 完成日志。
log "[phase3_dwi] Done: ${SUBJECT_ID}"
