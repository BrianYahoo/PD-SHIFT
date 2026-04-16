#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config
# 加载 conda、FSL、FreeSurfer、ANTs 等工具环境。
setup_tools_env

# 检查当前 step 依赖的 Python 解释器是否存在。
require_cmd "$PYTHON_BIN"

# 如果参考对比结果已经存在，则直接跳过。
if [[ -f "${COMPARE_DIR}/summary_metrics.csv" && -f "${COMPARE_DIR}/summary_metrics.json" && -f "${COMPARE_DIR}/summary.md" ]]; then
  log "[phase4_summary] Step3 already done for ${SUBJECT_ID}"
  exit 0
fi

# 调用比较脚本，把 FC 和 SC 分别与参考结果进行对比。
"$PYTHON_BIN" "${UTILS_DIR}/compare_reference.py" \
  --final-dir "${FINAL_DIR}" \
  --subject-id "${SUBJECT_ID}" \
  --dataset-type "${DATASET_TYPE}" \
  --fc-reference-root "${FC_REFERENCE_ROOT}" \
  --sc-reference-root "${SC_REFERENCE_ROOT}" \
  --out-dir "${COMPARE_DIR}"
