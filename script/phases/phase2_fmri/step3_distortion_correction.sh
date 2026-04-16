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
require_cmd fslroi
require_cmd fslmerge
require_cmd topup
require_cmd applytopup

# 定义本 step 的输入输出路径。
FUNC_INPUT="${FMRI_DIR}/func_stc.nii.gz"
FUNC_OUTPUT="${FMRI_DIR}/func_topup.nii.gz"
FUNC_REF_NII="${FMRI_FUNC_REF_INPUT}"
FUNC_REF_JSON="${FMRI_FUNC_REF_JSON}"

# 回填 stepview 中的输入。
link_step_product_nifti 3 1 "distortion_input" "$FUNC_INPUT"

# 如果畸变校正结果已经存在且可正常读取，则直接回填 stepview 并跳过。
if nifti_is_readable "$FUNC_OUTPUT"; then
  link_step_product_nifti 3 2 "distortion_output" "$FUNC_OUTPUT"
  log "[phase2_fmri] Step3 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

# 如果输出文件存在但损坏，则先清掉，避免旧半成品污染重跑。
if [[ -f "$FUNC_OUTPUT" ]]; then
  log "[phase2_fmri] Step3 detected unreadable output, rebuilding for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  rm -f "$FUNC_OUTPUT"
fi

# 先判断当前 trial 是否满足 topup 的执行条件。
read -r RUN_TOPUP MAIN_PE REF_PE <<<"$("$PYTHON_BIN" - "$FMRI_FUNC_JSON" "$FUNC_REF_JSON" "$FMRI_DO_TOPUP" <<'PY'
import json
import os
import sys

main_json = sys.argv[1]
ref_json = sys.argv[2]
flag = sys.argv[3]
main = json.load(open(main_json, "r", encoding="utf-8"))
ref = {}
if ref_json and os.path.exists(ref_json):
    ref = json.load(open(ref_json, "r", encoding="utf-8"))
main_pe = str(main.get("PhaseEncodingDirection", "")).strip()
ref_pe = str(ref.get("PhaseEncodingDirection", "")).strip()
run_topup = flag == "1" and bool(main_pe) and bool(ref_pe) and main_pe != ref_pe and os.path.exists(ref_json)
print(int(run_topup), main_pe or "NA", ref_pe or "NA")
PY
)"

# 如果缺少反向相位编码参考，或者两个方向相同，则直接沿用输入。
if [[ "$RUN_TOPUP" != "1" || ! -f "$FUNC_REF_NII" || ! -f "$FUNC_REF_JSON" ]]; then
  ln -sfn "$FUNC_INPUT" "$FUNC_OUTPUT"
  link_step_product_nifti 3 2 "distortion_output" "$FUNC_OUTPUT"
  exit 0
fi

# 生成 topup 所需的采集参数表。
"$PYTHON_BIN" - "$FMRI_FUNC_JSON" "$FUNC_REF_JSON" "${FMRI_DIR}/topup_acqparams.txt" <<'PY'
import json
import sys

main = json.load(open(sys.argv[1], "r", encoding="utf-8"))
ref = json.load(open(sys.argv[2], "r", encoding="utf-8"))
out = sys.argv[3]
mapping = {"i": (1, 0, 0), "i-": (-1, 0, 0), "j": (0, 1, 0), "j-": (0, -1, 0), "k": (0, 0, 1), "k-": (0, 0, -1)}
v1 = mapping.get(main.get("PhaseEncodingDirection", ""), (0, 0, 0))
v2 = mapping.get(ref.get("PhaseEncodingDirection", ""), (0, 0, 0))
readout = float(main.get("TotalReadoutTime", ref.get("TotalReadoutTime", 0.05)))
with open(out, "w", encoding="utf-8") as f:
    f.write(f"{v1[0]} {v1[1]} {v1[2]} {readout:.6f}\n")
    f.write(f"{v2[0]} {v2[1]} {v2[2]} {readout:.6f}\n")
PY

# 抽取主功能像与参考像的第一个 volume，用于 topup。
fslroi "$FUNC_INPUT" "${FMRI_DIR}/topup_b0_main.nii.gz" 0 1
fslroi "$FUNC_REF_NII" "${FMRI_DIR}/topup_b0_ref.nii.gz" 0 1
fslmerge -t "${FMRI_DIR}/topup_b0_pair.nii.gz" "${FMRI_DIR}/topup_b0_main.nii.gz" "${FMRI_DIR}/topup_b0_ref.nii.gz"

# 执行 topup 与 applytopup。
topup --imain="${FMRI_DIR}/topup_b0_pair.nii.gz" --datain="${FMRI_DIR}/topup_acqparams.txt" --config=b02b0.cnf --out="${FMRI_DIR}/topup_base" --iout="${FMRI_DIR}/topup_iout.nii.gz" --fout="${FMRI_DIR}/topup_field.nii.gz" >"${FMRI_DIR}/topup.log" 2>&1
applytopup --imain="$FUNC_INPUT" --datain="${FMRI_DIR}/topup_acqparams.txt" --inindex=1 --topup="${FMRI_DIR}/topup_base" --method=jac --out="$FUNC_OUTPUT" >"${FMRI_DIR}/applytopup.log" 2>&1

# 回填 stepview 中的输出。
link_step_product_nifti 3 2 "distortion_output" "$FUNC_OUTPUT"
