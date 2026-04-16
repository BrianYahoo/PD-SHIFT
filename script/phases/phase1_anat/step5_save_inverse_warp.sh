#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config

# 定义当前 step 的核心输入输出。
STEP5_MANIFEST="${PHASE1_ANAT_STEP5_DIR}/manifest.tsv"
REG_PREFIX="${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_"
SAVE_AFFINE="${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_0GenericAffine.mat"
SAVE_WARP="${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_1Warp.nii.gz"
SAVE_INV_WARP="${PHASE1_ANAT_STEP5_DIR}/native_to_mni2009b_1InverseWarp.nii.gz"

# 输出当前 step 的开始日志。
log "[phase1_anat] Step5 save inverse warp for ${SUBJECT_ID}"

# 如果当前 step 的主要结果都已存在，则直接跳过。
if [[ -f "${STEP5_MANIFEST}" && -f "${SAVE_AFFINE}" && -f "${SAVE_WARP}" && ( ! -f "${REG_PREFIX}1InverseWarp.nii.gz" || -f "${SAVE_INV_WARP}" ) ]]; then
  log "[phase1_anat] Step5 already done for ${SUBJECT_ID}"
  exit 0
fi

# 保存从 MNI2009b 回到个体 native space 所需的形变矩阵，供后续图谱逆变换直接复用。
cp -f "${REG_PREFIX}0GenericAffine.mat" "${SAVE_AFFINE}"
cp -f "${REG_PREFIX}1Warp.nii.gz" "${SAVE_WARP}"
if [[ -f "${REG_PREFIX}1InverseWarp.nii.gz" ]]; then
  cp -f "${REG_PREFIX}1InverseWarp.nii.gz" "${SAVE_INV_WARP}"
fi

# 写出当前 step 的输出清单。
cat > "${STEP5_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
forward_affine	${SAVE_AFFINE}
forward_warp	${SAVE_WARP}
inverse_warp	${SAVE_INV_WARP}
EOF
