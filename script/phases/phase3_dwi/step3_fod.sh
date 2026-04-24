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
require_cmd dwi2response
require_cmd dwi2fod
require_cmd mtnormalise

STEP3_LOG="${DWI_DIR}/step3_fod.log"

# 如果 FOD 归一化结果已经存在，则直接跳过。
if [[ -f "${DWI_DIR}/wm_response.txt" && -f "${DWI_DIR}/gm_response.txt" && -f "${DWI_DIR}/csf_response.txt" && -f "${DWI_DIR}/wmfod_norm.mif" && -f "${DWI_DIR}/gmfod_norm.mif" && -f "${DWI_DIR}/csffod_norm.mif" ]]; then
  log "[phase3_dwi] Step3 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果响应函数还不存在，则先估计 WM/GM/CSF 三类响应函数。
if [[ ! -f "${DWI_DIR}/wm_response.txt" ]]; then
  run_logged "${STEP3_LOG}" dwi2response dhollander "${DWI_DIR}/dwi_preproc_bias.mif" \
    "${DWI_DIR}/wm_response.txt" "${DWI_DIR}/gm_response.txt" "${DWI_DIR}/csf_response.txt" \
    -mask "${DWI_DIR}/dwi_mask.mif"
fi

# 如果归一化后的 FOD 还不存在，则执行 MSMT-CSD 和 mtnormalise。
if [[ ! -f "${DWI_DIR}/wmfod_norm.mif" ]]; then
  run_logged "${STEP3_LOG}" dwi2fod msmt_csd "${DWI_DIR}/dwi_preproc_bias.mif" \
    "${DWI_DIR}/wm_response.txt" "${DWI_DIR}/wmfod.mif" \
    "${DWI_DIR}/gm_response.txt" "${DWI_DIR}/gmfod.mif" \
    "${DWI_DIR}/csf_response.txt" "${DWI_DIR}/csffod.mif" \
    -mask "${DWI_DIR}/dwi_mask.mif" \
    -lmax "${DWI_LMAX},0,0"
  run_logged "${STEP3_LOG}" mtnormalise \
    "${DWI_DIR}/wmfod.mif" "${DWI_DIR}/wmfod_norm.mif" \
    "${DWI_DIR}/gmfod.mif" "${DWI_DIR}/gmfod_norm.mif" \
    "${DWI_DIR}/csffod.mif" "${DWI_DIR}/csffod_norm.mif" \
    -mask "${DWI_DIR}/dwi_mask.mif"
fi
