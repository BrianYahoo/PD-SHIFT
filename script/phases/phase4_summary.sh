#!/usr/bin/env bash
set -euo pipefail

# 计算当前入口脚本所在目录，后面用它去定位 step 子脚本。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common.sh"

# 按顺序定义 phase4_summary 需要执行的 step 子脚本。
PHASE4_STEPS=(
  "phase4_summary/step1_collect_outputs.sh"
  "phase4_summary/step2_export_tvp_model_inputs.sh"
  "phase4_summary/step3_compare_reference.sh"
  "phase4_summary/step4_write_report.sh"
)

# 依次执行每个 phase4_summary step。
for step_script in "${PHASE4_STEPS[@]}"; do
  bash "${SCRIPT_DIR}/phases/${step_script}"
done

# 在入口层输出 phase4_summary 完成日志。
load_config
log "[phase4_summary] Done: ${SUBJECT_ID}"
