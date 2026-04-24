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

# 检查当前 step 依赖的命令是否存在。
require_cmd tckgen
require_cmd tcksift2

STEP5_LOG="${DWI_DIR}/step5_tractography.log"

# 如果 tractography 和 SIFT2 权重都已存在，则直接跳过。
if [[ -f "${DWI_DIR}/tracks.tck" && -f "${DWI_DIR}/sift2_weights.txt" ]]; then
  log "[phase3_dwi] Step5 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果全脑纤维束文件还不存在，则执行 ACT + backtrack 追踪。
if [[ ! -f "${DWI_DIR}/tracks.tck" ]]; then
  run_logged "${STEP5_LOG}" tckgen "${DWI_DIR}/wmfod_norm.mif" "${DWI_DIR}/tracks.tck" \
    -algorithm iFOD2 \
    -act "${DWI_DIR}/5tt_dwi.mif" \
    -backtrack \
    -seed_gmwmi "${DWI_DIR}/gmwmi_seed.mif" \
    -maxlength "$TRACT_MAX_LENGTH" \
    -minlength "$TRACT_MIN_LENGTH" \
    -angle "$TRACT_MAX_ANGLE" \
    -select "$STREAMLINES" \
    -nthreads "$NTHREADS"
fi

# 如果 SIFT2 权重还不存在，则基于追踪结果和 FOD 估计 streamline 权重。
if [[ ! -f "${DWI_DIR}/sift2_weights.txt" ]]; then
  run_logged "${STEP5_LOG}" tcksift2 "${DWI_DIR}/tracks.tck" "${DWI_DIR}/wmfod_norm.mif" "${DWI_DIR}/sift2_weights.txt" -act "${DWI_DIR}/5tt_dwi.mif" -nthreads "$NTHREADS"
fi
