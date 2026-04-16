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
FUNC_INPUT="${FMRI_DIR}/func_regress.nii.gz"
FUNC_OUTPUT="${FMRI_DIR}/func_filter.nii.gz"
FILTER_QC="${FMRI_DIR}/${SUBJECT_ID}_${FMRI_TRIAL_NAME}_filter_qc.json"

# 读取当前 trial 的 TR，用于时间带通滤波。
TR_VALUE="$("$PYTHON_BIN" - "$FMRI_FUNC_JSON" "${DEFAULT_FUNC_TR:-}" "${FUNC_REQUIRE_JSON_TR:-0}" <<'PY'
import json
import sys

json_path = sys.argv[1]
default_tr = sys.argv[2]
require_json_tr = sys.argv[3] == "1"
try:
    data = json.load(open(json_path, "r", encoding="utf-8"))
    if "RepetitionTime" in data:
        print(float(data["RepetitionTime"]))
    elif require_json_tr:
        raise ValueError(f"Missing RepetitionTime in {json_path}")
    elif default_tr:
        print(float(default_tr))
    else:
        raise ValueError(f"Missing RepetitionTime in {json_path} and no DEFAULT_FUNC_TR fallback is configured")
except Exception as exc:
    if require_json_tr:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
    if default_tr:
        print(float(default_tr))
    else:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)
PY
)"

# 回填 stepview 中的输入。
link_step_product_nifti 9 1 "filter_input" "$FUNC_INPUT"

# 如果滤波结果已经存在，则直接回填 stepview 并跳过。
if [[ -f "$FUNC_OUTPUT" && -f "$FILTER_QC" ]]; then
  link_step_product_nifti 9 2 "filter_output" "$FUNC_OUTPUT"
  log "[phase2_fmri] Step9 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 对时间序列执行带通滤波。
"$PYTHON_BIN" "${UTILS_DIR}/fmri_temporal_filter.py" \
  --func "$FUNC_INPUT" \
  --brain-mask "${FMRI_DIR}/gs_mask_func.nii.gz" \
  --tr "$TR_VALUE" \
  --low-cut "$FMRI_LOW_CUT_HZ" \
  --high-cut "$FMRI_HIGH_CUT_HZ" \
  --output-func "$FUNC_OUTPUT" \
  --output-qc "$FILTER_QC"

# 回填 stepview 中的输出。
link_step_product_nifti 9 2 "filter_output" "$FUNC_OUTPUT"
