#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config

# 定义当前 step 的核心输入输出。
STEP4_MANIFEST="${PHASE1_ANAT_STEP4_DIR}/manifest.tsv"
WARP_REVIEW_NOTE="${PHASE1_ANAT_STEP4_DIR}/warpdrive_review.md"
WARP_REVIEW_OK="${PHASE1_ANAT_STEP4_DIR}/warpdrive_review.ok"
WARP_REVIEW_SKIP="${PHASE1_ANAT_STEP4_DIR}/warpdrive_review.skipped"
REG_PREFIX="${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_"

# 输出当前 step 的开始日志。
log "[phase1_anat] Step4 warpdrive review for ${SUBJECT_ID}"

# 如果当前 step 已经留下可复用结论，则直接跳过。
if [[ -f "${STEP4_MANIFEST}" && ( -f "${WARP_REVIEW_SKIP}" || -f "${WARP_REVIEW_OK}" ) ]]; then
  log "[phase1_anat] Step4 already done for ${SUBJECT_ID}"
  exit 0
fi

# 始终写出人工复核说明，供需要时直接打开检查。
cat > "${WARP_REVIEW_NOTE}" <<EOF
# WarpDrive Review

- subject: ${SUBJECT_ID}
- native_t1_brain: ${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz
- aparc_aseg: ${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz
- distal_mni: ${PHASE1_ANAT_STEP3_DIR}/distal6_mni.nii.gz
- affine: ${REG_PREFIX}0GenericAffine.mat
- warp: ${REG_PREFIX}1Warp.nii.gz

需要人工微调时，请在 WarpDrive 中检查 STN、GPe、GPi 的边界与形变场。
确认通过后创建空文件：

${WARP_REVIEW_OK}
EOF

# 默认不做人工微调；只有显式要求时才阻塞在这一步。
if [[ "${WARPDRIVE_REVIEW_REQUIRED}" != "1" ]]; then
  touch "${WARP_REVIEW_SKIP}"
  cat > "${STEP4_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
review_mode	skipped
review_note	${WARP_REVIEW_NOTE}
review_skip_flag	${WARP_REVIEW_SKIP}
EOF
  log "[phase1_anat] Step4 skipped for ${SUBJECT_ID}"
  exit 0
fi

# 如果要求人工微调，则必须看到确认标记文件后才继续往下走。
[[ -f "${WARP_REVIEW_OK}" ]] || die "Manual WarpDrive review required: ${WARP_REVIEW_OK}"

cat > "${STEP4_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
review_mode	required
review_note	${WARP_REVIEW_NOTE}
review_ok_flag	${WARP_REVIEW_OK}
EOF
