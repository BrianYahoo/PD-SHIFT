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
STEP3_MANIFEST="${PHASE1_ANAT_STEP3_DIR}/manifest.tsv"
REG_PREFIX="${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_"
SAVE_AFFINE="${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_0GenericAffine.mat"
SAVE_WARP="${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_1Warp.nii.gz"
SAVE_INV_WARP="${PHASE1_ANAT_STEP5_DIR}/native_to_mni2009b_1InverseWarp.nii.gz"
STEP5_SOURCE_AFFINE=""
STEP5_SOURCE_WARP=""
STEP5_SOURCE_INV_WARP=""
STEP5_TRANSFORM_LAYOUT=""

resolve_step5_transform_inputs() {
  STEP5_SOURCE_AFFINE=""
  STEP5_SOURCE_WARP=""
  STEP5_SOURCE_INV_WARP=""
  STEP5_TRANSFORM_LAYOUT="$(read_manifest_value "${STEP3_MANIFEST}" "transform_layout")"

  if [[ -f "${STEP3_MANIFEST}" ]]; then
    STEP5_SOURCE_AFFINE="$(read_manifest_value "${STEP3_MANIFEST}" "forward_affine")"
    STEP5_SOURCE_WARP="$(read_manifest_value "${STEP3_MANIFEST}" "forward_warp")"
    STEP5_SOURCE_INV_WARP="$(read_manifest_value "${STEP3_MANIFEST}" "inverse_warp")"
  fi

  [[ -n "${STEP5_SOURCE_WARP}" ]] || STEP5_SOURCE_WARP="${REG_PREFIX}1Warp.nii.gz"

  if [[ -z "${STEP5_SOURCE_AFFINE}" && -f "${REG_PREFIX}0GenericAffine.mat" ]]; then
    STEP5_SOURCE_AFFINE="${REG_PREFIX}0GenericAffine.mat"
  fi

  if [[ -z "${STEP5_SOURCE_INV_WARP}" ]]; then
    if [[ -f "${REG_PREFIX}1InverseWarp.nii.gz" ]]; then
      STEP5_SOURCE_INV_WARP="${REG_PREFIX}1InverseWarp.nii.gz"
    elif [[ -f "${REG_PREFIX}0InverseWarp.nii.gz" ]]; then
      STEP5_SOURCE_INV_WARP="${REG_PREFIX}0InverseWarp.nii.gz"
    fi
  fi

  if [[ -n "${STEP5_SOURCE_AFFINE}" && ! -f "${STEP5_SOURCE_AFFINE}" && ! -f "${REG_PREFIX}0GenericAffine.mat" && -f "${REG_PREFIX}0Warp.nii.gz" ]]; then
    STEP5_SOURCE_AFFINE=""
    STEP5_TRANSFORM_LAYOUT="composite_warp_only"
  fi

  if [[ -z "${STEP5_TRANSFORM_LAYOUT}" ]]; then
    if [[ -n "${STEP5_SOURCE_AFFINE}" ]]; then
      STEP5_TRANSFORM_LAYOUT="affine_plus_warp"
    else
      STEP5_TRANSFORM_LAYOUT="composite_warp_only"
    fi
  fi
}

# 输出当前 step 的开始日志。
log "[phase1_anat] Step5 save inverse warp for ${SUBJECT_ID}"

resolve_step5_transform_inputs
[[ -f "${STEP5_SOURCE_WARP}" ]] || die "Missing step3 forward warp: ${STEP5_SOURCE_WARP}"
[[ -z "${STEP5_SOURCE_AFFINE}" || -f "${STEP5_SOURCE_AFFINE}" ]] || die "Missing step3 forward affine: ${STEP5_SOURCE_AFFINE}"
[[ -z "${STEP5_SOURCE_INV_WARP}" || -f "${STEP5_SOURCE_INV_WARP}" ]] || die "Missing step3 inverse warp: ${STEP5_SOURCE_INV_WARP}"

# 如果当前 step 的主要结果都已存在，则直接跳过。
if [[ -f "${STEP5_MANIFEST}" && -f "${SAVE_WARP}" && ( -z "${STEP5_SOURCE_AFFINE}" || -f "${SAVE_AFFINE}" ) && ( -z "${STEP5_SOURCE_INV_WARP}" || -f "${SAVE_INV_WARP}" ) ]]; then
  log "[phase1_anat] Step5 already done for ${SUBJECT_ID}"
  exit 0
fi

# 保存从 MNI2009b 回到个体 native space 所需的形变矩阵，供后续图谱逆变换直接复用。
if [[ -n "${STEP5_SOURCE_AFFINE}" ]]; then
  cp -f "${STEP5_SOURCE_AFFINE}" "${SAVE_AFFINE}"
else
  rm -f "${SAVE_AFFINE}"
fi
cp -f "${STEP5_SOURCE_WARP}" "${SAVE_WARP}"
if [[ -n "${STEP5_SOURCE_INV_WARP}" ]]; then
  cp -f "${STEP5_SOURCE_INV_WARP}" "${SAVE_INV_WARP}"
else
  rm -f "${SAVE_INV_WARP}"
fi

# 写出当前 step 的输出清单。
cat > "${STEP5_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
transform_layout	${STEP5_TRANSFORM_LAYOUT}
forward_affine	$( [[ -n "${STEP5_SOURCE_AFFINE}" ]] && echo "${SAVE_AFFINE}" || echo "" )
forward_warp	${SAVE_WARP}
inverse_warp	$( [[ -n "${STEP5_SOURCE_INV_WARP}" ]] && echo "${SAVE_INV_WARP}" || echo "" )
EOF
