#!/usr/bin/env bash
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

load_config
setup_tools_env

WB_COMMAND="${CARET7DIR}/wb_command"
STANDARD_MESH_DIR="${HCPPIPEDIR}/global/templates/standard_mesh_atlases"
require_cmd "$PYTHON_BIN"
require_cmd "$WB_COMMAND"
require_cmd mris_convert

STEP7_MANIFEST="${PHASE1_ANAT_STEP7_DIR}/manifest.tsv"
LOG_DIR="${PHASE1_ANAT_STEP7_DIR}/logs"
NATIVE_SURF_DIR="${PHASE1_ANAT_STEP7_DIR}/native"
FSLR_MESH_K="${PHASE1_TISSUE_PROFILE_FSLR_MESH_K:-32}"
HIGHRES_MESH_K="${PHASE1_TISSUE_PROFILE_HIGHRES_MESH_K:-164}"
FSLR_DIR="${PHASE1_ANAT_STEP7_DIR}/fsLR${FSLR_MESH_K}k"
PLOT_DIR="${PHASE1_ANAT_VIS_DIR}/hierarchy"

ROI_MASTER_TSV="${PIPELINE_ROOT}/framework/details/roi.tsv"
T1_NATIVE="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
T2_NATIVE="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz"
HYBRID_ATLAS="${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz"
SURFER_SUBJECT_DIR="${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}"

REGIONAL_CSV="${PHASE1_ANAT_STEP7_DIR}/${SUBJECT_ID}_desc-t1t2_myelin_88.csv"
MYELIN_VOLUME="${PHASE1_ANAT_STEP7_DIR}/${SUBJECT_ID}_desc-myelin_t1wdivt2w.nii.gz"
T1_DSCALAR="${FSLR_DIR}/${SUBJECT_ID}.T1w.${FSLR_MESH_K}k_fs_LR.dscalar.nii"
T2_DSCALAR="${FSLR_DIR}/${SUBJECT_ID}.T2w.${FSLR_MESH_K}k_fs_LR.dscalar.nii"
MYELIN_DSCALAR="${FSLR_DIR}/${SUBJECT_ID}.Myelin.${FSLR_MESH_K}k_fs_LR.dscalar.nii"
T1_PLOT="${PLOT_DIR}/t1w_${FSLR_MESH_K}k_fsLR.png"
T2_PLOT="${PLOT_DIR}/t2w_${FSLR_MESH_K}k_fsLR.png"
MYELIN_PLOT="${PLOT_DIR}/myelin_t1wdivt2w_${FSLR_MESH_K}k_fsLR.png"

mkdir -p "${LOG_DIR}" "${NATIVE_SURF_DIR}" "${FSLR_DIR}" "${PLOT_DIR}"

log "[phase1_anat] Step7 T1/T2/Myelin profiles for ${SUBJECT_ID}"

write_step7_manifest() {
  cat > "${STEP7_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
status	$1
tissue_profile_enable	${PHASE1_TISSUE_PROFILE_ENABLE:-0}
tissue_profile_cifti_enable	${PHASE1_TISSUE_PROFILE_CIFTI_ENABLE:-0}
surface_plot_env	${PHASE1_SURFACE_PLOT_ENV:-osmesa}
surface_plot_python	${SURFACE_PLOT_PYTHON:-}
regional_csv	${REGIONAL_CSV}
myelin_volume	${MYELIN_VOLUME}
t1_dscalar	${T1_DSCALAR}
t2_dscalar	${T2_DSCALAR}
myelin_dscalar	${MYELIN_DSCALAR}
t1_plot	${T1_PLOT}
t2_plot	${T2_PLOT}
myelin_plot	${MYELIN_PLOT}
EOF
}

reset_step7_surface_outputs() {
  rm -f "${STEP7_MANIFEST}"
  rm -f "${LOG_DIR}"/*
  rm -f "${NATIVE_SURF_DIR}"/*
  rm -f "${FSLR_DIR}"/*
  rm -f "${T1_PLOT}" "${T2_PLOT}" "${MYELIN_PLOT}"
}

run_surface_plot() {
  case "${PHASE1_SURFACE_PLOT_ENV:-osmesa}" in
    osmesa)
      SURFACE_PLOT_PYTHON="${PHASE1_SURFACE_PLOT_OSMESA_PYTHON:-/data/bryang/project/CNS/tools/surfplot_osmesa_env/bin/python}"
      ;;
    mri|mri_env)
      SURFACE_PLOT_PYTHON="${PHASE1_SURFACE_PLOT_MRI_PYTHON:-${PYTHON_BIN}}"
      ;;
    *)
      die "Unsupported PHASE1_SURFACE_PLOT_ENV: ${PHASE1_SURFACE_PLOT_ENV}"
      ;;
  esac

  [[ -x "${SURFACE_PLOT_PYTHON}" ]] || die "Missing surface plot python: ${SURFACE_PLOT_PYTHON}"

  if [[ "${PHASE1_SURFACE_PLOT_ENV:-osmesa}" == "osmesa" ]]; then
    "${SURFACE_PLOT_PYTHON}" "$@"
    return 0
  fi

  if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a "${SURFACE_PLOT_PYTHON}" "$@"
  else
    "${SURFACE_PLOT_PYTHON}" "$@"
  fi
}

normalize_mris_convert_shape_output() {
  local expected_path="$1"
  local hemi_fs="$2"
  local normalized_basename=""
  local prefixed_path=""

  [[ -f "${expected_path}" ]] && return 0

  normalized_basename="$(basename "${expected_path}")"
  prefixed_path="$(dirname "${expected_path}")/${hemi_fs}h.${normalized_basename}"
  if [[ -f "${prefixed_path}" ]]; then
    mv -f "${prefixed_path}" "${expected_path}"
    return 0
  fi

  die "Missing mris_convert shape output: ${expected_path}"
}

if [[ "${PHASE1_TISSUE_PROFILE_ENABLE:-0}" != "1" ]]; then
  write_step7_manifest "disabled"
  log "[phase1_anat] Step7 disabled by config for ${SUBJECT_ID}"
  exit 0
fi

if [[ ! -f "${T2_NATIVE}" ]]; then
  write_step7_manifest "skipped_no_t2"
  log "[phase1_anat] Step7 skipped because T2 is unavailable for ${SUBJECT_ID}"
  exit 0
fi

if [[ -f "${STEP7_MANIFEST}" && -f "${REGIONAL_CSV}" && -f "${MYELIN_VOLUME}" ]] \
  && { [[ "${PHASE1_TISSUE_PROFILE_CIFTI_ENABLE:-0}" != "1" ]] || { [[ -f "${T1_DSCALAR}" && -f "${T2_DSCALAR}" && -f "${MYELIN_DSCALAR}" && -f "${T1_PLOT}" && -f "${T2_PLOT}" && -f "${MYELIN_PLOT}" ]]; }; }; then
  log "[phase1_anat] Step7 already done for ${SUBJECT_ID}"
  exit 0
fi

if [[ "${PHASE1_TISSUE_PROFILE_CIFTI_ENABLE:-0}" == "1" ]]; then
  reset_step7_surface_outputs
fi

[[ -f "${T1_NATIVE}" ]] || die "Missing T1 for Step7: ${T1_NATIVE}"
[[ -f "${HYBRID_ATLAS}" ]] || die "Missing hybrid atlas for Step7: ${HYBRID_ATLAS}"
[[ -d "${SURFER_SUBJECT_DIR}" ]] || die "Missing FreeSurfer/FastSurfer subject dir: ${SURFER_SUBJECT_DIR}"
[[ -d "${STANDARD_MESH_DIR}" ]] || die "Missing HCP standard mesh atlas dir: ${STANDARD_MESH_DIR}"

"${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step7/extract_t1t2_myelin_profiles.py" \
  --t1 "${T1_NATIVE}" \
  --t2 "${T2_NATIVE}" \
  --atlas "${HYBRID_ATLAS}" \
  --roi-tsv "${ROI_MASTER_TSV}" \
  --output-csv "${REGIONAL_CSV}" \
  --output-myelin "${MYELIN_VOLUME}"

copy_surface_native() {
  local hemi="$1"
  local hemi_fs="$2"
  local structure="$3"
  local white_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.white.native.surf.gii"
  local pial_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.pial.native.surf.gii"
  local midthickness_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.midthickness.native.surf.gii"
  local sphere_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.sphere.native.surf.gii"
  local sphere_reg_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.sphere.reg.native.surf.gii"
  local thickness_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.thickness.native.shape.gii"
  local thickness_abs="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.thickness.abs.native.shape.gii"
  local roi_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.roi.native.shape.gii"
  local sulc_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.sulc.native.shape.gii"
  local sulc_inverted="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.sulc.inverted.native.shape.gii"
  local regsphere_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.sphere.reg.reg_LR.native.surf.gii"
  local target_sphere="${STANDARD_MESH_DIR}/${hemi}.sphere.${FSLR_MESH_K}k_fs_LR.surf.gii"
  local atlasroi="${STANDARD_MESH_DIR}/${hemi}.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii"
  local fs_sphere="${STANDARD_MESH_DIR}/fs_${hemi}/fsaverage.${hemi}.sphere.${HIGHRES_MESH_K}k_fs_${hemi}.surf.gii"
  local def_sphere="${STANDARD_MESH_DIR}/fs_${hemi}/fs_${hemi}-to-fs_LR_fsaverage.${hemi}_LR.spherical_std.${HIGHRES_MESH_K}k_fs_${hemi}.surf.gii"
  local midthickness_fslr="${FSLR_DIR}/${SUBJECT_ID}.${hemi}.midthickness.${FSLR_MESH_K}k_fs_LR.surf.gii"
  local inflated_fslr="${FSLR_DIR}/${SUBJECT_ID}.${hemi}.inflated.${FSLR_MESH_K}k_fs_LR.surf.gii"
  local very_inflated_fslr="${FSLR_DIR}/${SUBJECT_ID}.${hemi}.very_inflated.${FSLR_MESH_K}k_fs_LR.surf.gii"
  local sulc_fslr="${FSLR_DIR}/${SUBJECT_ID}.${hemi}.sulc.${FSLR_MESH_K}k_fs_LR.shape.gii"

  mris_convert --to-scanner "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.white" "${white_native}" >"${LOG_DIR}/${hemi}_mris_convert_white.log" 2>&1
  mris_convert --to-scanner "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.pial" "${pial_native}" >"${LOG_DIR}/${hemi}_mris_convert_pial.log" 2>&1
  mris_convert "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.sphere" "${sphere_native}" >"${LOG_DIR}/${hemi}_mris_convert_sphere.log" 2>&1
  mris_convert "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.sphere.reg" "${sphere_reg_native}" >"${LOG_DIR}/${hemi}_mris_convert_sphere_reg.log" 2>&1
  mris_convert -c "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.thickness" "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.white" "${thickness_native}" >"${LOG_DIR}/${hemi}_mris_convert_thickness.log" 2>&1
  normalize_mris_convert_shape_output "${thickness_native}" "${hemi_fs}"
  mris_convert -c "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.sulc" "${SURFER_SUBJECT_DIR}/surf/${hemi_fs}h.white" "${sulc_native}" >"${LOG_DIR}/${hemi}_mris_convert_sulc.log" 2>&1
  normalize_mris_convert_shape_output "${sulc_native}" "${hemi_fs}"

  "${WB_COMMAND}" -surface-average "${midthickness_native}" -surf "${white_native}" -surf "${pial_native}" >"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -set-structure "${white_native}" "${structure}" -surface-type ANATOMICAL -surface-secondary-type GRAY_WHITE >>"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -set-structure "${pial_native}" "${structure}" -surface-type ANATOMICAL -surface-secondary-type PIAL >>"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -set-structure "${midthickness_native}" "${structure}" -surface-type ANATOMICAL -surface-secondary-type MIDTHICKNESS >>"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -set-structure "${sphere_native}" "${structure}" -surface-type SPHERICAL >>"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -set-structure "${sphere_reg_native}" "${structure}" -surface-type SPHERICAL >>"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -set-structure "${thickness_native}" "${structure}" >>"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -set-structure "${sulc_native}" "${structure}" >>"${LOG_DIR}/${hemi}_surface_average.log" 2>&1
  "${WB_COMMAND}" -metric-math "abs(thickness)" "${thickness_abs}" -var thickness "${thickness_native}" >"${LOG_DIR}/${hemi}_thickness.log" 2>&1
  mv "${thickness_abs}" "${thickness_native}"
  "${WB_COMMAND}" -metric-math "thickness > 0" "${roi_native}" -var thickness "${thickness_native}" >>"${LOG_DIR}/${hemi}_thickness.log" 2>&1
  "${WB_COMMAND}" -metric-fill-holes "${midthickness_native}" "${roi_native}" "${roi_native}" >>"${LOG_DIR}/${hemi}_thickness.log" 2>&1
  "${WB_COMMAND}" -metric-remove-islands "${midthickness_native}" "${roi_native}" "${roi_native}" >>"${LOG_DIR}/${hemi}_thickness.log" 2>&1
  "${WB_COMMAND}" -metric-math "var * -1" "${sulc_inverted}" -var var "${sulc_native}" >"${LOG_DIR}/${hemi}_sulc.log" 2>&1
  mv "${sulc_inverted}" "${sulc_native}"

  "${WB_COMMAND}" -surface-sphere-project-unproject "${sphere_reg_native}" "${fs_sphere}" "${def_sphere}" "${regsphere_native}" >"${LOG_DIR}/${hemi}_regsphere.log" 2>&1
  "${WB_COMMAND}" -set-structure "${regsphere_native}" "${structure}" -surface-type SPHERICAL >>"${LOG_DIR}/${hemi}_regsphere.log" 2>&1

  "${WB_COMMAND}" -surface-resample "${midthickness_native}" "${regsphere_native}" "${target_sphere}" BARYCENTRIC "${midthickness_fslr}" >"${LOG_DIR}/${hemi}_resample_surface.log" 2>&1
  "${WB_COMMAND}" -set-structure "${midthickness_fslr}" "${structure}" -surface-type ANATOMICAL -surface-secondary-type MIDTHICKNESS >>"${LOG_DIR}/${hemi}_resample_surface.log" 2>&1
  "${WB_COMMAND}" -surface-generate-inflated "${midthickness_fslr}" "${inflated_fslr}" "${very_inflated_fslr}" >>"${LOG_DIR}/${hemi}_resample_surface.log" 2>&1
  "${WB_COMMAND}" -set-structure "${inflated_fslr}" "${structure}" -surface-type INFLATED >>"${LOG_DIR}/${hemi}_resample_surface.log" 2>&1
  "${WB_COMMAND}" -set-structure "${very_inflated_fslr}" "${structure}" -surface-type VERY_INFLATED >>"${LOG_DIR}/${hemi}_resample_surface.log" 2>&1

  "${WB_COMMAND}" -metric-resample "${sulc_native}" "${regsphere_native}" "${target_sphere}" ADAP_BARY_AREA "${sulc_fslr}" \
    -area-surfs "${midthickness_native}" "${midthickness_fslr}" \
    -current-roi "${roi_native}" >"${LOG_DIR}/${hemi}_resample_sulc.log" 2>&1
  "${WB_COMMAND}" -metric-mask "${sulc_fslr}" "${atlasroi}" "${sulc_fslr}" >>"${LOG_DIR}/${hemi}_resample_sulc.log" 2>&1
}

map_volume_metric() {
  local hemi="$1"
  local structure="$2"
  local volume_path="$3"
  local map_name="$4"
  local native_metric="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.${map_name}.native.func.gii"
  local native_white="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.white.native.surf.gii"
  local native_pial="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.pial.native.surf.gii"
  local native_mid="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.midthickness.native.surf.gii"
  local regsphere_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.sphere.reg.reg_LR.native.surf.gii"
  local roi_native="${NATIVE_SURF_DIR}/${SUBJECT_ID}.${hemi}.roi.native.shape.gii"
  local target_sphere="${STANDARD_MESH_DIR}/${hemi}.sphere.${FSLR_MESH_K}k_fs_LR.surf.gii"
  local atlasroi="${STANDARD_MESH_DIR}/${hemi}.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii"
  local fslr_mid="${FSLR_DIR}/${SUBJECT_ID}.${hemi}.midthickness.${FSLR_MESH_K}k_fs_LR.surf.gii"
  local fslr_metric="${FSLR_DIR}/${SUBJECT_ID}.${hemi}.${map_name}.${FSLR_MESH_K}k_fs_LR.func.gii"

  "${WB_COMMAND}" -volume-to-surface-mapping "${volume_path}" "${native_mid}" "${native_metric}" \
    -ribbon-constrained "${native_white}" "${native_pial}" >"${LOG_DIR}/${hemi}_${map_name}_map.log" 2>&1
  "${WB_COMMAND}" -set-structure "${native_metric}" "${structure}" >>"${LOG_DIR}/${hemi}_${map_name}_map.log" 2>&1
  "${WB_COMMAND}" -metric-resample "${native_metric}" "${regsphere_native}" "${target_sphere}" ADAP_BARY_AREA "${fslr_metric}" \
    -area-surfs "${native_mid}" "${fslr_mid}" \
    -current-roi "${roi_native}" >"${LOG_DIR}/${hemi}_${map_name}_resample.log" 2>&1
  "${WB_COMMAND}" -metric-mask "${fslr_metric}" "${atlasroi}" "${fslr_metric}" >>"${LOG_DIR}/${hemi}_${map_name}_resample.log" 2>&1
}

if [[ "${PHASE1_TISSUE_PROFILE_CIFTI_ENABLE:-0}" == "1" ]]; then
  copy_surface_native "L" "l" "CORTEX_LEFT"
  copy_surface_native "R" "r" "CORTEX_RIGHT"

  map_volume_metric "L" "CORTEX_LEFT" "${T1_NATIVE}" "T1w"
  map_volume_metric "R" "CORTEX_RIGHT" "${T1_NATIVE}" "T1w"
  map_volume_metric "L" "CORTEX_LEFT" "${T2_NATIVE}" "T2w"
  map_volume_metric "R" "CORTEX_RIGHT" "${T2_NATIVE}" "T2w"

  "${WB_COMMAND}" -metric-math "T1 / (T2 + 0.000001)" "${FSLR_DIR}/${SUBJECT_ID}.L.Myelin.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -var T1 "${FSLR_DIR}/${SUBJECT_ID}.L.T1w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -var T2 "${FSLR_DIR}/${SUBJECT_ID}.L.T2w.${FSLR_MESH_K}k_fs_LR.func.gii" >"${LOG_DIR}/L_myelin_metric.log" 2>&1
  "${WB_COMMAND}" -metric-math "T1 / (T2 + 0.000001)" "${FSLR_DIR}/${SUBJECT_ID}.R.Myelin.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -var T1 "${FSLR_DIR}/${SUBJECT_ID}.R.T1w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -var T2 "${FSLR_DIR}/${SUBJECT_ID}.R.T2w.${FSLR_MESH_K}k_fs_LR.func.gii" >"${LOG_DIR}/R_myelin_metric.log" 2>&1

  "${WB_COMMAND}" -cifti-create-dense-scalar "${T1_DSCALAR}" \
    -left-metric "${FSLR_DIR}/${SUBJECT_ID}.L.T1w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -roi-left "${STANDARD_MESH_DIR}/L.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    -right-metric "${FSLR_DIR}/${SUBJECT_ID}.R.T1w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -roi-right "${STANDARD_MESH_DIR}/R.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii" >"${LOG_DIR}/t1_dscalar.log" 2>&1
  "${WB_COMMAND}" -set-map-name "${T1_DSCALAR}" 1 "${SUBJECT_ID}_T1w" >>"${LOG_DIR}/t1_dscalar.log" 2>&1

  "${WB_COMMAND}" -cifti-create-dense-scalar "${T2_DSCALAR}" \
    -left-metric "${FSLR_DIR}/${SUBJECT_ID}.L.T2w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -roi-left "${STANDARD_MESH_DIR}/L.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    -right-metric "${FSLR_DIR}/${SUBJECT_ID}.R.T2w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -roi-right "${STANDARD_MESH_DIR}/R.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii" >"${LOG_DIR}/t2_dscalar.log" 2>&1
  "${WB_COMMAND}" -set-map-name "${T2_DSCALAR}" 1 "${SUBJECT_ID}_T2w" >>"${LOG_DIR}/t2_dscalar.log" 2>&1

  "${WB_COMMAND}" -cifti-create-dense-scalar "${MYELIN_DSCALAR}" \
    -left-metric "${FSLR_DIR}/${SUBJECT_ID}.L.Myelin.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -roi-left "${STANDARD_MESH_DIR}/L.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    -right-metric "${FSLR_DIR}/${SUBJECT_ID}.R.Myelin.${FSLR_MESH_K}k_fs_LR.func.gii" \
    -roi-right "${STANDARD_MESH_DIR}/R.atlasroi.${FSLR_MESH_K}k_fs_LR.shape.gii" >"${LOG_DIR}/myelin_dscalar.log" 2>&1
  "${WB_COMMAND}" -set-map-name "${MYELIN_DSCALAR}" 1 "${SUBJECT_ID}_Myelin_T1wDivT2w" >>"${LOG_DIR}/myelin_dscalar.log" 2>&1

  run_surface_plot "${UTILS_DIR}/phase1_anat/step7/plot_fslr_scalar_surfaces.py" \
    --left-surface "${FSLR_DIR}/${SUBJECT_ID}.L.inflated.${FSLR_MESH_K}k_fs_LR.surf.gii" \
    --right-surface "${FSLR_DIR}/${SUBJECT_ID}.R.inflated.${FSLR_MESH_K}k_fs_LR.surf.gii" \
    --left-metric "${FSLR_DIR}/${SUBJECT_ID}.L.T1w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    --right-metric "${FSLR_DIR}/${SUBJECT_ID}.R.T1w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    --left-bg "${FSLR_DIR}/${SUBJECT_ID}.L.sulc.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    --right-bg "${FSLR_DIR}/${SUBJECT_ID}.R.sulc.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    --title "${SUBJECT_ID} T1w ${FSLR_MESH_K}k fsLR" \
    --output "${T1_PLOT}" \
    --cmap "viridis"

  run_surface_plot "${UTILS_DIR}/phase1_anat/step7/plot_fslr_scalar_surfaces.py" \
    --left-surface "${FSLR_DIR}/${SUBJECT_ID}.L.inflated.${FSLR_MESH_K}k_fs_LR.surf.gii" \
    --right-surface "${FSLR_DIR}/${SUBJECT_ID}.R.inflated.${FSLR_MESH_K}k_fs_LR.surf.gii" \
    --left-metric "${FSLR_DIR}/${SUBJECT_ID}.L.T2w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    --right-metric "${FSLR_DIR}/${SUBJECT_ID}.R.T2w.${FSLR_MESH_K}k_fs_LR.func.gii" \
    --left-bg "${FSLR_DIR}/${SUBJECT_ID}.L.sulc.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    --right-bg "${FSLR_DIR}/${SUBJECT_ID}.R.sulc.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    --title "${SUBJECT_ID} T2w ${FSLR_MESH_K}k fsLR" \
    --output "${T2_PLOT}" \
    --cmap "magma"

  run_surface_plot "${UTILS_DIR}/phase1_anat/step7/plot_fslr_scalar_surfaces.py" \
    --left-surface "${FSLR_DIR}/${SUBJECT_ID}.L.inflated.${FSLR_MESH_K}k_fs_LR.surf.gii" \
    --right-surface "${FSLR_DIR}/${SUBJECT_ID}.R.inflated.${FSLR_MESH_K}k_fs_LR.surf.gii" \
    --left-metric "${FSLR_DIR}/${SUBJECT_ID}.L.Myelin.${FSLR_MESH_K}k_fs_LR.func.gii" \
    --right-metric "${FSLR_DIR}/${SUBJECT_ID}.R.Myelin.${FSLR_MESH_K}k_fs_LR.func.gii" \
    --left-bg "${FSLR_DIR}/${SUBJECT_ID}.L.sulc.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    --right-bg "${FSLR_DIR}/${SUBJECT_ID}.R.sulc.${FSLR_MESH_K}k_fs_LR.shape.gii" \
    --title "${SUBJECT_ID} Myelin T1w/T2w ${FSLR_MESH_K}k fsLR" \
    --output "${MYELIN_PLOT}" \
    --cmap "turbo"
fi

write_step7_manifest "done"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 7 1 "myelin_t1wdivt2w" "${MYELIN_VOLUME}"
