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
require_cmd mrconvert

STEP1_LOG="${DWI_DIR}/step1_import_raw.log"

# 定义 DWI 主数据和反向数据的输入路径。
DWI_NII="${INIT_STEP0_DIR}/dwi.nii.gz"
DWI_BVAL="${INIT_STEP0_DIR}/dwi.bval"
DWI_BVEC="${INIT_STEP0_DIR}/dwi.bvec"
DWI_JSON="${INIT_STEP0_DIR}/dwi.json"
DWI_JSON_FALLBACK="${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.json"
DWI_REV_NII="${INIT_STEP0_DIR}/dwi_rev.nii.gz"
DWI_REV_BVAL="${INIT_STEP0_DIR}/dwi_rev.bval"
DWI_REV_BVEC="${INIT_STEP0_DIR}/dwi_rev.bvec"
DWI_REV_JSON="${INIT_STEP0_DIR}/dwi_rev.json"
DWI_REV_JSON_FALLBACK="${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dir-rev_dwi.json"

# 检查主 DWI 输入是否存在。
[[ -f "$DWI_NII" ]] || die "Missing DWI"

if [[ ! -f "$DWI_JSON" && -f "$DWI_JSON_FALLBACK" ]]; then
  DWI_JSON="$DWI_JSON_FALLBACK"
fi

if [[ ! -f "$DWI_REV_JSON" && -f "$DWI_REV_JSON_FALLBACK" ]]; then
  DWI_REV_JSON="$DWI_REV_JSON_FALLBACK"
fi

[[ -f "$DWI_JSON" ]] || die "Missing DWI JSON"

# 如果 DWI 的 MRtrix 导入结果已齐全，则直接跳过。
if [[ -f "${DWI_DIR}/dwi_raw.mif" && ( ! -f "$DWI_REV_NII" || -f "${DWI_DIR}/dwi_rev_raw.mif" ) ]]; then
  log "[phase3_dwi] Step1 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果主 DWI 的 mif 版本还不存在，则先导入为 MRtrix 原生格式。
if [[ ! -f "${DWI_DIR}/dwi_raw.mif" ]]; then
  run_logged "${STEP1_LOG}" mrconvert "$DWI_NII" "${DWI_DIR}/dwi_raw.mif" -fslgrad "$DWI_BVEC" "$DWI_BVAL" -json_import "$DWI_JSON"
fi

# 如果反向相位编码 DWI 完整存在，则一并导入为 mif。
if [[ -f "$DWI_REV_NII" && -f "$DWI_REV_BVAL" && -f "$DWI_REV_BVEC" && -f "$DWI_REV_JSON" ]]; then
  if [[ ! -f "${DWI_DIR}/dwi_rev_raw.mif" ]]; then
    run_logged "${STEP1_LOG}" mrconvert "$DWI_REV_NII" "${DWI_DIR}/dwi_rev_raw.mif" -fslgrad "$DWI_REV_BVEC" "$DWI_REV_BVAL" -json_import "$DWI_REV_JSON"
  fi
fi
