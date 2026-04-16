#!/usr/bin/env bash
set -euo pipefail

# 计算当前入口脚本所在目录，后面用它去定位 step 子脚本。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config
# 入口层需要用 Python 检查 trial 是否为可处理的 4D timeseries。
setup_tools_env

# 按顺序定义 phase2_fmri 需要执行的 step 子脚本。
PHASE2_STEPS=(
  "phase2_fmri/step1_remove_start_images.sh"
  "phase2_fmri/step2_slice_timing.sh"
  "phase2_fmri/step3_distortion_correction.sh"
  "phase2_fmri/step4_motion_correction.sh"
  "phase2_fmri/step5_bbr.sh"
  "phase2_fmri/step6_spatially_smooth.sh"
  "phase2_fmri/step7_temporally_detrend.sh"
  "phase2_fmri/step8_regress_out_covariates.sh"
  "phase2_fmri/step9_temporally_filter.sh"
  "phase2_fmri/step10_scrubbing_mark.sh"
  "phase2_fmri/step11_extract_signal.sh"
)

# 读取当前受试者可用的所有 REST trial。
mapfile -t FMRI_TRIALS < <(list_fmri_trial_names)
if (( ${#FMRI_TRIALS[@]} == 0 )); then
  log "[phase2_fmri] No fMRI trials found for ${SUBJECT_ID}, skipping phase2"
  exit 0
fi

fmri_trial_timepoints() {
  local trial_name="$1"
  local trial_func="${INIT_STEP0_DIR}/trials/${trial_name}/func.nii.gz"
  [[ -f "$trial_func" ]] || trial_func="${INIT_STEP0_DIR}/func.nii.gz"
  [[ -f "$trial_func" ]] || return 1
  "$PYTHON_BIN" - "$trial_func" <<'PY'
import sys
import nibabel as nib

img = nib.load(sys.argv[1])
shape = img.shape
if len(shape) < 4:
    print(1)
else:
    print(int(shape[3]))
PY
}

# 依次执行每个 trial 的全部 phase2_fmri step。
processed_trials=0
for trial_name in "${FMRI_TRIALS[@]}"; do
  trial_timepoints="$(fmri_trial_timepoints "$trial_name" || true)"
  if [[ -z "$trial_timepoints" || "$trial_timepoints" -lt 2 ]]; then
    log "[phase2_fmri] Skipping non-timeseries fMRI trial ${trial_name} for ${SUBJECT_ID} (timepoints=${trial_timepoints:-NA})"
    continue
  fi
  processed_trials=$((processed_trials + 1))
  log "[phase2_fmri] Trial ${trial_name} for ${SUBJECT_ID}"
  for step_script in "${PHASE2_STEPS[@]}"; do
    FMRI_TRIAL_NAME="$trial_name" bash "${SCRIPT_DIR}/phases/${step_script}"
  done
done

# 在入口层输出 phase2_fmri 完成日志。
if (( processed_trials == 0 )); then
  log "[phase2_fmri] No processable fMRI timeseries for ${SUBJECT_ID}, skipping phase2"
  exit 0
fi
log "[phase2_fmri] Done: ${SUBJECT_ID}"
