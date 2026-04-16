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
FUNC_INPUT="${FMRI_DIR}/func_trim.nii.gz"
FUNC_STC="${FMRI_DIR}/func_stc.nii.gz"

# 读取当前 trial 的 TR，用于判断是否需要做 slice timing。
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
link_step_product_nifti 2 1 "slice_timing_input" "$FUNC_INPUT"

# 如果 slice timing 结果已经存在且可正常读取，则直接回填 stepview 并跳过。
if nifti_is_readable "$FUNC_STC"; then
  link_step_product_nifti 2 2 "slice_timing_output" "$FUNC_STC"
  log "[phase2_fmri] Step2 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 如果文件存在但已损坏，则先删掉后重建，避免后续步骤持续读取坏文件。
if [[ -f "$FUNC_STC" ]]; then
  log "[phase2_fmri] Step2 detected unreadable output, rebuilding for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  rm -f "$FUNC_STC"
fi

# 只有在 TR 大于阈值时才执行 slice timing；否则直接沿用输入。
if "$PYTHON_BIN" - "$TR_VALUE" "$FMRI_SLICE_TIMING_TR_THRESHOLD" <<'PY'
import sys
sys.exit(0 if float(sys.argv[1]) > float(sys.argv[2]) else 1)
PY
then
  "$PYTHON_BIN" "${UTILS_DIR}/phase2_fmri/step2/fmri_slice_timing.py" \
    --input "$FUNC_INPUT" \
    --json "$FMRI_FUNC_JSON" \
    --output "$FUNC_STC"
else
  ln -sfn "$FUNC_INPUT" "$FUNC_STC"
fi

# 回填 stepview 中的输出。
link_step_product_nifti 2 2 "slice_timing_output" "$FUNC_STC"
