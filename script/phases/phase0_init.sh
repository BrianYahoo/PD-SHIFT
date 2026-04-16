#!/usr/bin/env bash
set -euo pipefail

# 计算当前入口脚本所在目录，后面用它去定位 step 子脚本。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common.sh"

# phase0_init 当前只有一个标准化输入 step。
PHASE0_STEPS=(
  "phase0_init/step1_bids_standardize.sh"
)

# 依次执行 phase0_init 的全部 step。
for step_script in "${PHASE0_STEPS[@]}"; do
  bash "${SCRIPT_DIR}/phases/${step_script}"
done

# 在入口层输出 phase0_init 完成日志。
load_config
log "[phase0_init] Done: ${SUBJECT_ID}"
