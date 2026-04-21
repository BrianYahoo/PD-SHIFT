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
T2_NATIVE="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz"
T2_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz"
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
VIS_ALIGN_DIR="${PHASE1_ANAT_VIS_DIR}/align"
VIS_T1_ATLAS_DIR="${VIS_ALIGN_DIR}/t1/atlas"
VIS_T1_SUBCORTEX_DIR="${VIS_ALIGN_DIR}/t1/subcortex"
VIS_T2_ATLAS_DIR="${VIS_ALIGN_DIR}/t2/atlas"
VIS_T2_SUBCORTEX_DIR="${VIS_ALIGN_DIR}/t2/subcortex"
ROI_MASTER_TSV="${PIPELINE_ROOT}/framework/details/roi.tsv"
STEP6_USE_T2_VIS="0"
STEP5_MANIFEST="${PHASE1_ANAT_STEP5_DIR}/manifest.tsv"
STEP6_TRANSFORM_LAYOUT="$(read_manifest_value "${PHASE1_ANAT_STEP5_DIR}/manifest.tsv" "transform_layout")"
STEP6_FORWARD_AFFINE="$(read_manifest_value "${PHASE1_ANAT_STEP5_DIR}/manifest.tsv" "forward_affine")"
STEP6_FORWARD_WARP="$(read_manifest_value "${PHASE1_ANAT_STEP5_DIR}/manifest.tsv" "forward_warp")"
STEP6_SOURCE_STEP3_ENGINE="$(read_manifest_value "${PHASE1_ANAT_STEP3_DIR}/manifest.tsv" "registration_engine")"
STEP6_SOURCE_STEP5_MANIFEST_MTIME=""
STEP6_ANTS_TRANSFORMS=()
if [[ -f "${T2_BRAIN}" ]]; then
  STEP6_USE_T2_VIS="1"
fi
if [[ -f "${STEP5_MANIFEST}" ]]; then
  STEP6_SOURCE_STEP5_MANIFEST_MTIME="$(stat -c '%Y' "${STEP5_MANIFEST}")"
fi

[[ -n "${STEP6_FORWARD_WARP}" ]] || STEP6_FORWARD_WARP="${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_1Warp.nii.gz"
[[ -n "${STEP6_FORWARD_AFFINE}" ]] || STEP6_FORWARD_AFFINE="${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_0GenericAffine.mat"
[[ -f "${STEP6_FORWARD_WARP}" ]] || die "Missing step5 forward warp for Step6: ${STEP6_FORWARD_WARP}"
STEP6_ANTS_TRANSFORMS=(-t "${STEP6_FORWARD_WARP}")
if [[ -f "${STEP6_FORWARD_AFFINE}" ]]; then
  STEP6_ANTS_TRANSFORMS+=(-t "${STEP6_FORWARD_AFFINE}")
elif [[ "${STEP6_TRANSFORM_LAYOUT}" == "composite_warp_only" ]]; then
  log "[phase1_anat] Step6 applying composite warp-only transforms for ${SUBJECT_ID}"
fi

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

hybrid_atlas_complete() {
  [[ -f "${HYBRID_ATLAS}" && -f "${HYBRID_LABELS}" ]] || return 1
  "${PYTHON_BIN}" - "${HYBRID_ATLAS}" "${HYBRID_LABELS}" <<'PY'
import csv
import sys
import nibabel as nib
import numpy as np

atlas_values = {int(v) for v in np.unique(np.asarray(nib.load(sys.argv[1]).dataobj)) if float(v) > 0}
with open(sys.argv[2], "r", encoding="utf-8") as f:
    for row in csv.DictReader(f, delimiter="\t"):
        if int(row["index"]) not in atlas_values:
            raise SystemExit(1)
raise SystemExit(0)
PY
}

step6_outputs_ready() {
  local manifest_transform_layout=""
  local manifest_source_step3_engine=""
  local manifest_source_step5_manifest_mtime=""
  [[ -f "${STEP6_MANIFEST}" && -f "${DISTAL_NATIVE}" && -f "${SN_NATIVE}" && -f "${SUBC20_NATIVE}" && -f "${SUBC20_LABELS}" && -f "${HYBRID_ATLAS}" && -f "${HYBRID_LABELS}" ]] || return 1
  atlas_native_ready || return 1
  hybrid_atlas_complete || return 1
  compgen -G "${VIS_T1_ATLAS_DIR}/z=*.png" > /dev/null || return 1
  compgen -G "${VIS_T1_SUBCORTEX_DIR}/GPe/z=*.png" > /dev/null || return 1
  if [[ "${STEP6_USE_T2_VIS}" == "1" ]]; then
    compgen -G "${VIS_T2_ATLAS_DIR}/z=*.png" > /dev/null || return 1
    compgen -G "${VIS_T2_SUBCORTEX_DIR}/GPe/z=*.png" > /dev/null || return 1
  fi
  manifest_transform_layout="$(read_manifest_value "${STEP6_MANIFEST}" "transform_layout")"
  manifest_source_step3_engine="$(read_manifest_value "${STEP6_MANIFEST}" "source_step3_engine")"
  manifest_source_step5_manifest_mtime="$(read_manifest_value "${STEP6_MANIFEST}" "source_step5_manifest_mtime")"
  [[ "${manifest_transform_layout}" == "${STEP6_TRANSFORM_LAYOUT}" ]] || return 1
  [[ "${manifest_source_step3_engine}" == "${STEP6_SOURCE_STEP3_ENGINE}" ]] || return 1
  [[ "${manifest_source_step5_manifest_mtime}" == "${STEP6_SOURCE_STEP5_MANIFEST_MTIME}" ]] || return 1
}

# 输出当前 step 的开始日志。
log "[phase1_anat] Step6 distal inverse fusion for ${SUBJECT_ID}"

# 如果当前 step 的主要结果都已存在，则直接跳过。
if step6_outputs_ready; then
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
    "${STEP6_ANTS_TRANSFORMS[@]}" >"${PHASE1_ANAT_STEP6_DIR}/ants_apply_distal.log" 2>&1
fi

# 把黑质 atlas 同样逆向变换到当前个体的真实原生 T1 空间。
if [[ ! -f "${SN_NATIVE}" ]]; then
  antsApplyTransforms \
    -d 3 \
    -i "${SN_MNI}" \
    -r "${T1_NATIVE}" \
    -o "${SN_NATIVE}" \
    -n NearestNeighbor \
    "${STEP6_ANTS_TRANSFORMS[@]}" >"${PHASE1_ANAT_STEP6_DIR}/ants_apply_sn.log" 2>&1
fi

# 先把常规皮层下结构、DISTAL 与黑质合成为固定 20 ROI 皮层下图谱。
if [[ ! -f "${SUBC20_NATIVE}" || ! -f "${SUBC20_LABELS}" ]] || ! atlas_native_ready; then
  "${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step6/build_subcortical_atlas.py" \
    --aparc "${APARC_ASEG}" \
    --distal "${DISTAL_NATIVE}" \
    --distal-label-tsv "${DISTAL_LABELS}" \
    --sn "${SN_NATIVE}" \
    --sn-label-tsv "${SN_LABELS}" \
    --output-nii "${SUBC20_NATIVE}" \
    --output-tsv "${SUBC20_LABELS}"
fi

# 用固定 20 ROI 皮层下图谱覆盖 FreeSurfer 深部区域，输出最终 88 ROI Hybrid Atlas。
if [[ ! -f "${HYBRID_ATLAS}" || ! -f "${HYBRID_LABELS}" ]] || ! atlas_native_ready || ! hybrid_atlas_complete; then
  "${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step6/merge_custom_atlas.py" \
    --aparc "${APARC_ASEG}" \
    --subcortical "${SUBC20_NATIVE}" \
    --subcortical-label-tsv "${SUBC20_LABELS}" \
    --roi-master-tsv "${ROI_MASTER_TSV}" \
    --output "${HYBRID_ATLAS}" \
    --output-labels "${HYBRID_LABELS}"
fi

# 输出按 z 轴逐层的 atlas 叠加可视化，便于直接检查融合后的空间位置。
mkdir -p "${VIS_T1_ATLAS_DIR}" "${VIS_T1_SUBCORTEX_DIR}"
"${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step6/visualize_hybrid_atlas_overlay.py" \
  --base "${T1_NATIVE}" \
  --atlas "${HYBRID_ATLAS}" \
  --labels-tsv "${HYBRID_LABELS}" \
  --atlas-out-dir "${VIS_T1_ATLAS_DIR}" \
  --subcortex-out-dir "${VIS_T1_SUBCORTEX_DIR}"
if [[ "${STEP6_USE_T2_VIS}" == "1" ]]; then
  mkdir -p "${VIS_T2_ATLAS_DIR}" "${VIS_T2_SUBCORTEX_DIR}"
  "${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step6/visualize_hybrid_atlas_overlay.py" \
    --base "${T2_BRAIN}" \
    --atlas "${HYBRID_ATLAS}" \
    --labels-tsv "${HYBRID_LABELS}" \
    --atlas-out-dir "${VIS_T2_ATLAS_DIR}" \
    --subcortex-out-dir "${VIS_T2_SUBCORTEX_DIR}"
fi

# 写出当前 step 的输出清单。
cat > "${STEP6_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
transform_layout	${STEP6_TRANSFORM_LAYOUT}
source_step3_engine	${STEP6_SOURCE_STEP3_ENGINE}
source_step5_manifest_mtime	${STEP6_SOURCE_STEP5_MANIFEST_MTIME}
aparc_aseg	${APARC_ASEG}
distal_native	${DISTAL_NATIVE}
sn_native	${SN_NATIVE}
subc20_native	${SUBC20_NATIVE}
subc20_labels	${SUBC20_LABELS}
hybrid_atlas	${HYBRID_ATLAS}
hybrid_labels	${HYBRID_LABELS}
visualization_t1_atlas_dir	${VIS_T1_ATLAS_DIR}
visualization_t1_subcortex_dir	${VIS_T1_SUBCORTEX_DIR}
visualization_t2_available	${STEP6_USE_T2_VIS}
visualization_t2_atlas_dir	$( [[ "${STEP6_USE_T2_VIS}" == "1" ]] && echo "${VIS_T2_ATLAS_DIR}" || echo "" )
visualization_t2_subcortex_dir	$( [[ "${STEP6_USE_T2_VIS}" == "1" ]] && echo "${VIS_T2_SUBCORTEX_DIR}" || echo "" )
EOF

# 把当前 step 的关键结果链接到 stepview，便于快速核对。
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 1 "distal_native" "${DISTAL_NATIVE}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 2 "sn_native" "${SN_NATIVE}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 3 "subc20_native" "${SUBC20_NATIVE}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 6 4 "hybrid_atlas" "${HYBRID_ATLAS}"
