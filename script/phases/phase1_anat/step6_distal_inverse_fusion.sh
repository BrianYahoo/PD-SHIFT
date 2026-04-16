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
require_cmd antsApplyTransforms

# 定义当前 step 的核心输入输出。
STEP6_MANIFEST="${PHASE1_ANAT_STEP6_DIR}/manifest.tsv"
T1_NATIVE="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
DISTAL_MNI="${PHASE1_ANAT_STEP3_DIR}/distal6_mni.nii.gz"
DISTAL_LABELS="${PHASE1_ANAT_STEP3_DIR}/distal6_labels.tsv"
SN_MNI="${PHASE1_ANAT_STEP3_DIR}/sn2_mni.nii.gz"
SN_LABELS="${PHASE1_ANAT_STEP3_DIR}/sn2_labels.tsv"
DISTAL_NATIVE="${PHASE1_ANAT_STEP6_DIR}/distal6_native.nii.gz"
SN_NATIVE="${PHASE1_ANAT_STEP6_DIR}/sn2_native.nii.gz"
SUBC20_NATIVE="${PHASE1_ANAT_STEP6_DIR}/subc20_native.nii.gz"
SUBC20_LABELS="${PHASE1_ANAT_STEP6_DIR}/subc20_labels.tsv"
HYBRID_ATLAS="${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz"
HYBRID_LABELS="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"
VIS_ATLAS_DIR="${PHASE1_ANAT_DIR}/visualization/atlas"
VIS_SUBCORTEX_DIR="${PHASE1_ANAT_DIR}/visualization/subcortex"
ROI_MASTER_TSV="${PIPELINE_ROOT}/framework/details/roi.tsv"

atlas_native_ready() {
  [[ -f "${HYBRID_ATLAS}" ]] || return 1
  "${PYTHON_BIN}" - "${T1_NATIVE}" "${HYBRID_ATLAS}" <<'PY'
import sys
import nibabel as nib
import numpy as np

t1 = nib.load(sys.argv[1])
atlas = nib.load(sys.argv[2])
same_shape = t1.shape == atlas.shape
same_affine = np.allclose(t1.affine, atlas.affine)
raise SystemExit(0 if same_shape and same_affine else 1)
PY
}

# 输出当前 step 的开始日志。
log "[phase1_anat] Step6 distal inverse fusion for ${SUBJECT_ID}"

# 如果当前 step 的主要结果都已存在，则直接跳过。
if [[ -f "${STEP6_MANIFEST}" && -f "${DISTAL_NATIVE}" && -f "${SN_NATIVE}" && -f "${SUBC20_NATIVE}" && -f "${SUBC20_LABELS}" && -f "${HYBRID_ATLAS}" && -f "${HYBRID_LABELS}" ]] && atlas_native_ready && compgen -G "${VIS_ATLAS_DIR}/z=*.png" > /dev/null && compgen -G "${VIS_SUBCORTEX_DIR}/GPe/z=*.png" > /dev/null; then
  log "[phase1_anat] Step6 already done for ${SUBJECT_ID}"
  exit 0
fi

# 把 DISTAL 深部核团图谱逆向变换到当前个体的真实原生 T1 空间。
if [[ ! -f "${DISTAL_NATIVE}" ]]; then
  antsApplyTransforms \
    -d 3 \
    -i "${DISTAL_MNI}" \
    -r "${T1_NATIVE}" \
    -o "${DISTAL_NATIVE}" \
    -n NearestNeighbor \
    -t "${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_1Warp.nii.gz" \
    -t "${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_0GenericAffine.mat" >"${PHASE1_ANAT_STEP6_DIR}/ants_apply_distal.log" 2>&1
fi

# 把黑质 atlas 同样逆向变换到当前个体的真实原生 T1 空间。
if [[ ! -f "${SN_NATIVE}" ]]; then
  antsApplyTransforms \
    -d 3 \
    -i "${SN_MNI}" \
    -r "${T1_NATIVE}" \
    -o "${SN_NATIVE}" \
    -n NearestNeighbor \
    -t "${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_1Warp.nii.gz" \
    -t "${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_0GenericAffine.mat" >"${PHASE1_ANAT_STEP6_DIR}/ants_apply_sn.log" 2>&1
fi

# 先把常规皮层下结构、DISTAL 与黑质合成为固定 20 ROI 皮层下图谱。
if [[ ! -f "${SUBC20_NATIVE}" || ! -f "${SUBC20_LABELS}" ]] || ! atlas_native_ready; then
  "${PYTHON_BIN}" "${UTILS_DIR}/build_subcortical_atlas.py" \
    --aparc "${APARC_ASEG}" \
    --distal "${DISTAL_NATIVE}" \
    --distal-label-tsv "${DISTAL_LABELS}" \
    --sn "${SN_NATIVE}" \
    --sn-label-tsv "${SN_LABELS}" \
    --output-nii "${SUBC20_NATIVE}" \
    --output-tsv "${SUBC20_LABELS}"
fi

# 用固定 20 ROI 皮层下图谱覆盖 FreeSurfer 深部区域，输出最终 88 ROI Hybrid Atlas。
if [[ ! -f "${HYBRID_ATLAS}" || ! -f "${HYBRID_LABELS}" ]] || ! atlas_native_ready; then
  "${PYTHON_BIN}" "${UTILS_DIR}/merge_custom_atlas.py" \
    --aparc "${APARC_ASEG}" \
    --subcortical "${SUBC20_NATIVE}" \
    --subcortical-label-tsv "${SUBC20_LABELS}" \
    --roi-master-tsv "${ROI_MASTER_TSV}" \
    --output "${HYBRID_ATLAS}" \
    --output-labels "${HYBRID_LABELS}"
fi

# 输出按 z 轴逐层的 atlas 叠加可视化，便于直接检查融合后的空间位置。
mkdir -p "${VIS_ATLAS_DIR}"
mkdir -p "${VIS_SUBCORTEX_DIR}"
"${PYTHON_BIN}" "${UTILS_DIR}/visualize_hybrid_atlas_overlay.py" \
  --t1 "${T1_NATIVE}" \
  --atlas "${HYBRID_ATLAS}" \
  --labels-tsv "${HYBRID_LABELS}" \
  --atlas-out-dir "${VIS_ATLAS_DIR}" \
  --subcortex-out-dir "${VIS_SUBCORTEX_DIR}"

# 写出当前 step 的输出清单。
cat > "${STEP6_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
aparc_aseg	${APARC_ASEG}
distal_native	${DISTAL_NATIVE}
sn_native	${SN_NATIVE}
subc20_native	${SUBC20_NATIVE}
subc20_labels	${SUBC20_LABELS}
hybrid_atlas	${HYBRID_ATLAS}
hybrid_labels	${HYBRID_LABELS}
visualization_atlas_dir	${VIS_ATLAS_DIR}
visualization_subcortex_dir	${VIS_SUBCORTEX_DIR}
EOF

# 把当前 step 的关键结果链接到 stepview，便于快速核对。
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 1 "distal_native" "${DISTAL_NATIVE}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 2 "sn_native" "${SN_NATIVE}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 3 "subc20_native" "${SUBC20_NATIVE}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 4 "hybrid_atlas" "${HYBRID_ATLAS}"
