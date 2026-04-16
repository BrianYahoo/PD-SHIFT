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

# 检查当前 step 依赖的核心命令。
require_cmd "$PYTHON_BIN"
require_cmd antsRegistrationSyN.sh
require_cmd fslmaths

# 定义当前 step 的核心输入输出。
STEP3_MANIFEST="${PHASE1_ANAT_STEP3_DIR}/manifest.tsv"
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
MNI_BRAIN="${PHASE1_ANAT_STEP3_DIR}/mni2009b_brain.nii.gz"
DISTAL_MNI="${PHASE1_ANAT_STEP3_DIR}/distal6_mni.nii.gz"
DISTAL_LABELS="${PHASE1_ANAT_STEP3_DIR}/distal6_labels.tsv"
SN_MNI="${PHASE1_ANAT_STEP3_DIR}/sn2_mni.nii.gz"
SN_LABELS="${PHASE1_ANAT_STEP3_DIR}/sn2_labels.tsv"
REG_PREFIX="${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_"

# 输出当前 step 的开始日志。
log "[phase1_anat] Step3 subcortical SyN for ${SUBJECT_ID}"

# 如果当前 step 的主要结果都已存在，则直接跳过。
if [[ -f "${STEP3_MANIFEST}" && -f "${MNI_BRAIN}" && -f "${DISTAL_MNI}" && -f "${DISTAL_LABELS}" && -f "${SN_MNI}" && -f "${SN_LABELS}" && -f "${REG_PREFIX}1Warp.nii.gz" && -f "${REG_PREFIX}1InverseWarp.nii.gz" && -f "${REG_PREFIX}0GenericAffine.mat" ]]; then
  log "[phase1_anat] Step3 already done for ${SUBJECT_ID}"
  exit 0
fi

# 先准备 MNI2009b 的脑模板，用作固定模板侧的输入。
if [[ ! -f "${MNI_BRAIN}" ]]; then
  fslmaths "${MNI_T1}" -mas "${MNI_BRAINMASK}" "${MNI_BRAIN}"
fi

# 组装 DISTAL 的 6 个深部核团标签图，后续将它整体逆变换回个体 native space。
if [[ ! -f "${DISTAL_MNI}" || ! -f "${DISTAL_LABELS}" ]]; then
  "${PYTHON_BIN}" "${UTILS_DIR}/create_label_atlas.py" \
    --atlas-dir "${DISTAL_ATLAS_DIR}" \
    --roi-list "${CONFIG_DIR}/distal_gpe_gpi_stn_6.tsv" \
    --output-nii "${DISTAL_MNI}" \
    --output-tsv "${DISTAL_LABELS}"
fi

# 组装双侧黑质标签图，后续与 DISTAL 一起逆变换回 native space。
if [[ ! -f "${SN_MNI}" || ! -f "${SN_LABELS}" ]]; then
  "${PYTHON_BIN}" "${UTILS_DIR}/create_label_atlas.py" \
    --atlas-dir "${SN_ATLAS_DIR}" \
    --roi-list "${CONFIG_DIR}/sn_2.tsv" \
    --output-nii "${SN_MNI}" \
    --output-tsv "${SN_LABELS}"
fi

# 用锁死参数的 SyN 把 MNI2009b 配准到个体原生 T1，优先守住深部核团区域。
if [[ ! -f "${REG_PREFIX}1Warp.nii.gz" || ! -f "${REG_PREFIX}0GenericAffine.mat" ]]; then
  antsRegistrationSyN.sh \
    -d 3 \
    -f "${T1_BRAIN}" \
    -m "${MNI_BRAIN}" \
    -o "${REG_PREFIX}" \
    -t "${PHASE1_REG_TRANSFORM}" \
    -n "${NTHREADS}" >"${PHASE1_ANAT_STEP3_DIR}/ants_syn.log" 2>&1
fi

# 写出当前 step 的输出清单。
cat > "${STEP3_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
registration_engine	ANTs_SyN
locked_preset	${PHASE1_LEADDBS_PRESET}
fixed_image	${T1_BRAIN}
moving_image	${MNI_BRAIN}
distal_mni	${DISTAL_MNI}
distal_labels	${DISTAL_LABELS}
sn_mni	${SN_MNI}
sn_labels	${SN_LABELS}
forward_affine	${REG_PREFIX}0GenericAffine.mat
forward_warp	${REG_PREFIX}1Warp.nii.gz
inverse_warp	${REG_PREFIX}1InverseWarp.nii.gz
EOF

# 把当前 step 的关键模板结果链接到 stepview，便于快速核对。
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 1 "mni2009b_brain" "${MNI_BRAIN}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 2 "distal_mni" "${DISTAL_MNI}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 3 "sn_mni" "${SN_MNI}"
