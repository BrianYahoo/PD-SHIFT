#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset、surfer 类型和 subject 的配置。
load_config
# 加载 FreeSurfer / FastSurfer 等工具环境。
setup_tools_env

# 检查当前 step 依赖的核心命令。
require_cmd mri_convert
require_cmd mri_vol2vol
require_cmd mri_binarize
require_cmd mri_surf2volseg
if [[ "${SURFER_TYPE}" == "free" ]]; then
  require_cmd recon-all
  require_cmd mri_aparc2aseg
else
  require_cmd mris_ca_label
  [[ -f "${FASTSURFER_HOME}/run_fastsurfer.sh" ]] || die "Missing FastSurfer entrypoint: ${FASTSURFER_HOME}/run_fastsurfer.sh"
fi

# 定义当前 step 的核心输入输出。
STEP2_MANIFEST="${PHASE1_ANAT_STEP2_DIR}/manifest.tsv"
BIDS_T1_INPUT="${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.nii.gz"
T1_NATIVE_INPUT="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
T1_MASK="${PHASE1_ANAT_STEP1_DIR}/t1_brain_mask.nii.gz"
T1_FS_XMASK="${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_xmask.nii.gz"
T1_FS_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_brain.nii.gz"
T2_COREG_T1="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz"
T2_COREG_T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz"
SURFER_SUBJECTS_DIR="${PHASE1_ANAT_STEP2_DIR}/surfer_subjects"
SURFER_SUBJECT_DIR="${SURFER_SUBJECTS_DIR}/${SUBJECT_ID}"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
SURFER_DONE="${PHASE1_ANAT_STEP2_DIR}/surfer.done"
if [[ "${SURFER_TYPE}" == "free" ]]; then
  SURFER_ENGINE_LOG="${PHASE1_ANAT_STEP2_DIR}/recon-all.log"
else
  SURFER_ENGINE_LOG="${PHASE1_ANAT_STEP2_DIR}/fastsurfer.log"
fi
FS_DONE="${SURFER_SUBJECT_DIR}/scripts/recon-all.done"
FS_ERROR="${SURFER_SUBJECT_DIR}/scripts/recon-all.error"
SURFER_LH_WHITE="${SURFER_SUBJECT_DIR}/surf/lh.white"
SURFER_RH_WHITE="${SURFER_SUBJECT_DIR}/surf/rh.white"
SURFER_BRAINMASK="${SURFER_SUBJECT_DIR}/mri/brainmask.mgz"
SURFER_BRAINMASK_AUTO="${SURFER_SUBJECT_DIR}/mri/brainmask.auto.mgz"
SURFER_ORIG="${SURFER_SUBJECT_DIR}/mri/orig.mgz"
SURFER_NU="${SURFER_SUBJECT_DIR}/mri/nu.mgz"
SURFER_T1="${SURFER_SUBJECT_DIR}/mri/T1.mgz"
SURFER_APARC_ASEG_MGZ="${SURFER_SUBJECT_DIR}/mri/aparc+aseg.mgz"
FASTSURFER_DEEPSEG_MGZ="${SURFER_SUBJECT_DIR}/mri/aparc.DKTatlas+aseg.deep.mgz"
FASTSURFER_MAPPED_MGZ="${SURFER_SUBJECT_DIR}/mri/aparc.DKTatlas+aseg.mapped.mgz"
FASTSURFER_ORIG_NU="${SURFER_SUBJECT_DIR}/mri/orig_nu.mgz"
FASTSURFER_MASK="${SURFER_SUBJECT_DIR}/mri/mask.mgz"
FASTSURFER_FSAPARC_LH="${SURFER_SUBJECT_DIR}/label/lh.aparc.annot"
FASTSURFER_FSAPARC_RH="${SURFER_SUBJECT_DIR}/label/rh.aparc.annot"
FASTSURFER_DESIKAN_MGZ="${SURFER_SUBJECT_DIR}/mri/aparc+aseg.desikan.mgz"
FASTSURFER_DESIKAN_LH_CLASSIFIER="${FREESURFER_HOME}/average/lh.curvature.buckner40.filled.desikan_killiany.2010-03-25.gcs"
FASTSURFER_DESIKAN_RH_CLASSIFIER="${FREESURFER_HOME}/average/rh.curvature.buckner40.filled.desikan_killiany.2010-03-25.gcs"
FS_EXPERT_OPTS="${PHASE1_ANAT_STEP2_DIR}/recon-all.expert.opts"
PHASE0_STEP1_MANIFEST="${PHASE0_INIT_STEP1_DIR}/manifest.tsv"
FASTSURFER_REQUIRED_DESIKAN_LABELS=(1001 1032 1033 2001 2032 2033)
SURFER_T2_INPUT=""
SURFER_USE_T2="0"
if [[ "${PHASE1_T2_SURFER_ENABLE:-0}" == "1" && -f "${T2_COREG_T1}" ]]; then
  SURFER_T2_INPUT="${T2_COREG_T1}"
  SURFER_USE_T2="1"
fi
SURFER_USE_T2_EFFECTIVE="${SURFER_USE_T2}"
SURFER_HIRES_EFFECTIVE="0"
SURFER_HIRES_REASON="disabled"
SURFER_T1_INPUT_EFFECTIVE="${T1_NATIVE_INPUT}"
SURFER_T1_BRAIN_EFFECTIVE="${T1_BRAIN}"
SURFER_T1_MASK_EFFECTIVE="${T1_MASK}"
SURFER_T1_FS_XMASK_EFFECTIVE="${T1_FS_XMASK}"
SURFER_T1_FS_BRAIN_EFFECTIVE="${T1_FS_BRAIN}"
SURFER_T2_INPUT_EFFECTIVE="${SURFER_T2_INPUT}"
SURFER_HIRES_INPUT_PREP_DIR="${PHASE1_ANAT_STEP2_DIR}/hires_input"
SURFER_HIRES_INPUT_CROP_APPLIED="0"
SURFER_HIRES_INPUT_CROP_BOUNDS=""
SURFER_ENGINE_LOG_CURRENT=""
SURFER_RETRY_ATTEMPT="1"
SURFER_RETRY_MAX="3"
if [[ "${SURFER_TYPE}" == "free" ]]; then
  if "${PYTHON_BIN}" - "${T1_NATIVE_INPUT}" <<'PY' >/dev/null 2>&1
import sys
import nibabel as nib

img = nib.load(sys.argv[1])
zooms = img.header.get_zooms()[:3]
raise SystemExit(0 if any(float(z) < 0.999 for z in zooms) else 1)
PY
  then
    SURFER_HIRES_EFFECTIVE="1"
    SURFER_HIRES_REASON="submillimeter_input"
  fi
  if [[ "${PHASE1_SURFER_HIRES:-0}" == "1" ]]; then
    SURFER_HIRES_EFFECTIVE="1"
    if [[ "${SURFER_HIRES_REASON}" == "submillimeter_input" ]]; then
      SURFER_HIRES_REASON="config+submillimeter_input"
    else
      SURFER_HIRES_REASON="config"
    fi
  fi
fi

# 把 FreeSurfer/FastSurfer 的 SUBJECTS_DIR 导出给后续命令使用。
export SUBJECTS_DIR="${SURFER_SUBJECTS_DIR}"
mkdir -p "${SURFER_SUBJECTS_DIR}"

surfer_surfaces_ready() {
  [[ -f "${SURFER_LH_WHITE}" && -f "${SURFER_RH_WHITE}" ]]
}

surfer_pial_surfaces_ready() {
  [[ -f "${SURFER_SUBJECT_DIR}/surf/lh.pial" && -f "${SURFER_SUBJECT_DIR}/surf/rh.pial" ]]
}

fastsurfer_surfaces_ready() {
  surfer_surfaces_ready || return 1
  surfer_pial_surfaces_ready || return 1
}

surfer_core_volumes_ready() {
  [[ -f "${SURFER_ORIG}" && -f "${SURFER_NU}" && -f "${SURFER_T1}" && -f "${SURFER_BRAINMASK}" ]]
}

surfer_aparc_mgz_ready() {
  [[ -f "${SURFER_APARC_ASEG_MGZ}" ]]
}

freesurfer_engine_outputs_ready() {
  [[ "${SURFER_TYPE}" == "free" ]] || return 1
  surfer_surfaces_ready || return 1
  surfer_core_volumes_ready || return 1
  surfer_aparc_mgz_ready || return 1
}

fastsurfer_segmentation_ready() {
  [[ -f "${SURFER_ORIG}" && -f "${FASTSURFER_ORIG_NU}" && -f "${FASTSURFER_MASK}" && -f "${FASTSURFER_DEEPSEG_MGZ}" ]]
}

fastsurfer_mapped_aparc_ready() {
  [[ -f "${FASTSURFER_MAPPED_MGZ}" ]]
}

ensure_fastsurfer_surface_inputs() {
  mkdir -p "${SURFER_SUBJECT_DIR}/mri"
  if [[ -f "${FASTSURFER_ORIG_NU}" && ! -f "${SURFER_NU}" ]]; then
    cp -f "${FASTSURFER_ORIG_NU}" "${SURFER_NU}"
  fi
  if [[ -f "${FASTSURFER_MASK}" && ! -f "${SURFER_BRAINMASK}" ]]; then
    cp -f "${FASTSURFER_MASK}" "${SURFER_BRAINMASK}"
    cp -f "${FASTSURFER_MASK}" "${SURFER_BRAINMASK_AUTO}" || true
  fi
}

ensure_fastsurfer_aparc_aseg() {
  if [[ ! -f "${SURFER_APARC_ASEG_MGZ}" && -f "${FASTSURFER_MAPPED_MGZ}" ]]; then
    cp -f "${FASTSURFER_MAPPED_MGZ}" "${SURFER_APARC_ASEG_MGZ}"
  fi
}

fastsurfer_recoverable_segstats_failure() {
  [[ -f "${SURFER_ENGINE_LOG}" ]] || return 1
  grep -q "TypeError: The seg object is not a numpy.ndarray of <class 'numpy.integer'>" "${SURFER_ENGINE_LOG}" || return 1
  fastsurfer_surfaces_ready || return 1
  surfer_core_volumes_ready || return 1
  fastsurfer_mapped_aparc_ready || return 1
}

fastsurfer_engine_outputs_ready() {
  fastsurfer_surfaces_ready || return 1
  surfer_core_volumes_ready || return 1
  fastsurfer_mapped_aparc_ready || return 1
}

freesurfer_uses_v8_defaults() {
  [[ "${SURFER_TYPE}" == "free" ]] || return 1
  [[ "${PHASE1_FREESURFER_V8_GUARD:-0}" == "1" ]] || return 1
  if [[ -f "${SURFER_SUBJECT_DIR}/mri/synthstrip.mgz" || -f "${SURFER_SUBJECT_DIR}/mri/synthseg.rca.mgz" ]]; then
    return 0
  fi
  [[ -f "${SURFER_ENGINE_LOG}" ]] || return 1
  grep -q -- "-synthstrip" "${SURFER_ENGINE_LOG}" || return 1
  grep -q -- "-synthseg" "${SURFER_ENGINE_LOG}" || return 1
  grep -q -- "-synthmorph" "${SURFER_ENGINE_LOG}" || return 1
}

freesurfer_t2_pial_refine_segfault() {
  local log_path="${SURFER_ENGINE_LOG_CURRENT:-${SURFER_ENGINE_LOG}}"
  [[ "${SURFER_TYPE}" == "free" ]] || return 1
  [[ "${SURFER_USE_T2_EFFECTIVE:-0}" == "1" ]] || return 1
  [[ -f "${log_path}" ]] || return 1
  grep -q "Command terminated by signal 11" "${log_path}" || return 1
  grep -q "#@# Refine Pial Surfs w/ T2/FLAIR" "${log_path}" || return 1
  grep -q -- "--mmvol T2.mgz T2" "${log_path}" || return 1
}

freesurfer_hires_fov_exceeds_limit() {
  local image_path="${1:-}"
  [[ -f "${image_path}" ]] || return 1
  "${PYTHON_BIN}" - "${image_path}" <<'PY' >/dev/null 2>&1
import sys
import nibabel as nib

img = nib.load(sys.argv[1])
shape = img.shape[:3]
zooms = img.header.get_zooms()[:3]
fov = [float(shape[i]) * float(zooms[i]) for i in range(3)]
raise SystemExit(0 if any(v > 256.0 + 1e-3 for v in fov) else 1)
PY
}

prepare_freesurfer_hires_inputs_if_needed() {
  local prep_output=""
  local key=""
  local value=""
  SURFER_T1_INPUT_EFFECTIVE="${T1_NATIVE_INPUT}"
  SURFER_T1_BRAIN_EFFECTIVE="${T1_BRAIN}"
  SURFER_T1_MASK_EFFECTIVE="${T1_MASK}"
  SURFER_T1_FS_XMASK_EFFECTIVE="${T1_FS_XMASK}"
  SURFER_T1_FS_BRAIN_EFFECTIVE="${T1_FS_BRAIN}"
  SURFER_T2_INPUT_EFFECTIVE="${SURFER_T2_INPUT}"
  SURFER_HIRES_INPUT_CROP_APPLIED="0"
  SURFER_HIRES_INPUT_CROP_BOUNDS=""

  [[ "${SURFER_TYPE}" == "free" ]] || return 0
  [[ "${SURFER_HIRES_EFFECTIVE:-0}" == "1" ]] || return 0
  freesurfer_hires_fov_exceeds_limit "${T1_NATIVE_INPUT}" || return 0

  mkdir -p "${SURFER_HIRES_INPUT_PREP_DIR}"
  prep_output="$("${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step2/prepare_freesurfer_hires_inputs.py" \
    --t1 "${T1_NATIVE_INPUT}" \
    --mask "${T1_MASK}" \
    --brain "${T1_BRAIN}" \
    --fs-brain "${T1_FS_BRAIN}" \
    --xmask "${T1_FS_XMASK}" \
    $( [[ "${SURFER_USE_T2_EFFECTIVE}" == "1" ]] && printf '%s %q' '--t2' "${SURFER_T2_INPUT}" ) \
    --out-dir "${SURFER_HIRES_INPUT_PREP_DIR}")"

  while IFS='=' read -r key value; do
    case "${key}" in
      crop_applied) SURFER_HIRES_INPUT_CROP_APPLIED="${value}" ;;
      crop_bounds) SURFER_HIRES_INPUT_CROP_BOUNDS="${value}" ;;
      t1_path) SURFER_T1_INPUT_EFFECTIVE="${value}" ;;
      brain_path) SURFER_T1_BRAIN_EFFECTIVE="${value}" ;;
      fs_brain_path) SURFER_T1_FS_BRAIN_EFFECTIVE="${value}" ;;
      mask_path) SURFER_T1_MASK_EFFECTIVE="${value}" ;;
      xmask_path) SURFER_T1_FS_XMASK_EFFECTIVE="${value}" ;;
      t2_path) SURFER_T2_INPUT_EFFECTIVE="${value}" ;;
    esac
  done <<< "${prep_output}"

  if [[ "${SURFER_HIRES_INPUT_CROP_APPLIED}" == "1" ]]; then
    log "[phase1_anat] Step2 cropped hires FreeSurfer input to stay within 256 mm FOV (${SURFER_HIRES_INPUT_CROP_BOUNDS})"
  fi
}

aparc_native_ready() {
  [[ -f "${APARC_ASEG}" ]] || return 1
  "${PYTHON_BIN}" - "${T1_NATIVE_INPUT}" "${APARC_ASEG}" <<'PY'
import sys
import nibabel as nib
import numpy as np

t1 = nib.load(sys.argv[1])
aparc = nib.load(sys.argv[2])
same_shape = t1.shape == aparc.shape
same_affine = np.allclose(t1.affine, aparc.affine)
raise SystemExit(0 if same_shape and same_affine else 1)
PY
}

volume_has_labels() {
  local volume_path="$1"
  shift
  [[ -f "${volume_path}" ]] || return 1
  "${PYTHON_BIN}" - "${volume_path}" "$@" <<'PY'
import sys
import nibabel as nib
import numpy as np

values = {int(v) for v in np.unique(np.asarray(nib.load(sys.argv[1]).dataobj)) if float(v) > 0}
required = {int(v) for v in sys.argv[2:]}
raise SystemExit(0 if required.issubset(values) else 1)
PY
}

fastsurfer_desikan_repair_enabled() {
  [[ "${SURFER_TYPE}" == "fast" && "${PHASE1_FASTSURFER_DESIKAN_REPAIR_ENABLE:-1}" == "1" ]]
}

fastsurfer_desikan_labels_ready_in_volume() {
  local volume_path="$1"
  volume_has_labels "${volume_path}" "${FASTSURFER_REQUIRED_DESIKAN_LABELS[@]}"
}

step2_native_outputs_ready() {
  aparc_native_ready || return 1
  if fastsurfer_desikan_repair_enabled; then
    fastsurfer_desikan_labels_ready_in_volume "${APARC_ASEG}" || return 1
  fi
}

repair_fastsurfer_desikan_aparc() {
  local tmp_lh="${SURFER_SUBJECT_DIR}/label/lh.aparc.desikan_tmp.annot"
  local tmp_rh="${SURFER_SUBJECT_DIR}/label/rh.aparc.desikan_tmp.annot"
  local tmp_mgz="${FASTSURFER_DESIKAN_MGZ%.mgz}.tmp.mgz"

  fastsurfer_desikan_repair_enabled || return 0
  [[ -f "${SURFER_APARC_ASEG_MGZ}" ]] || return 1
  if fastsurfer_desikan_labels_ready_in_volume "${SURFER_APARC_ASEG_MGZ}"; then
    return 0
  fi

  [[ -f "${SURFER_SUBJECT_DIR}/mri/aseg.presurf.mgz" ]] || die "Missing FastSurfer aseg.presurf.mgz for Desikan repair: ${SURFER_SUBJECT_DIR}/mri/aseg.presurf.mgz"
  [[ -f "${SURFER_SUBJECT_DIR}/surf/lh.sphere.reg" && -f "${SURFER_SUBJECT_DIR}/surf/rh.sphere.reg" ]] || die "Missing FastSurfer sphere.reg for Desikan repair: ${SURFER_SUBJECT_DIR}/surf"
  [[ -f "${FASTSURFER_DESIKAN_LH_CLASSIFIER}" && -f "${FASTSURFER_DESIKAN_RH_CLASSIFIER}" ]] || die "Missing FreeSurfer Desikan classifiers under ${FREESURFER_HOME}/average"

  log "[phase1_anat] Step2 supplementing FastSurfer DKT output with Desikan cortical labels for ${SUBJECT_ID}"
  mris_ca_label \
    -l "${SURFER_SUBJECT_DIR}/label/lh.cortex.label" \
    -aseg "${SURFER_SUBJECT_DIR}/mri/aseg.presurf.mgz" \
    -seed 1234 \
    "${SUBJECT_ID}" \
    lh \
    "${SURFER_SUBJECT_DIR}/surf/lh.sphere.reg" \
    "${FASTSURFER_DESIKAN_LH_CLASSIFIER}" \
    "${tmp_lh}" >"${PHASE1_ANAT_STEP2_DIR}/mris_ca_label_lh.log" 2>&1
  mris_ca_label \
    -l "${SURFER_SUBJECT_DIR}/label/rh.cortex.label" \
    -aseg "${SURFER_SUBJECT_DIR}/mri/aseg.presurf.mgz" \
    -seed 1234 \
    "${SUBJECT_ID}" \
    rh \
    "${SURFER_SUBJECT_DIR}/surf/rh.sphere.reg" \
    "${FASTSURFER_DESIKAN_RH_CLASSIFIER}" \
    "${tmp_rh}" >"${PHASE1_ANAT_STEP2_DIR}/mris_ca_label_rh.log" 2>&1
  mri_surf2volseg \
    --o "${tmp_mgz}" \
    --label-cortex \
    --i "${SURFER_SUBJECT_DIR}/mri/aseg.mgz" \
    --threads "${NTHREADS}" \
    --lh-annot "${tmp_lh}" 1000 \
    --lh-cortex-mask "${SURFER_SUBJECT_DIR}/label/lh.cortex.label" \
    --lh-white "${SURFER_SUBJECT_DIR}/surf/lh.white" \
    --lh-pial "${SURFER_SUBJECT_DIR}/surf/lh.pial" \
    --rh-annot "${tmp_rh}" 2000 \
    --rh-cortex-mask "${SURFER_SUBJECT_DIR}/label/rh.cortex.label" \
    --rh-white "${SURFER_SUBJECT_DIR}/surf/rh.white" \
    --rh-pial "${SURFER_SUBJECT_DIR}/surf/rh.pial" >"${PHASE1_ANAT_STEP2_DIR}/mri_surf2volseg_desikan.log" 2>&1
  fastsurfer_desikan_labels_ready_in_volume "${tmp_mgz}" || die "FastSurfer Desikan repair still missing required cortical labels: ${tmp_mgz}"

  mv -f "${tmp_lh}" "${FASTSURFER_FSAPARC_LH}"
  mv -f "${tmp_rh}" "${FASTSURFER_FSAPARC_RH}"
  mv -f "${tmp_mgz}" "${SURFER_APARC_ASEG_MGZ}"
}

ensure_freesurfer_brainmask() {
  local tmp_brain="${PHASE1_ANAT_STEP2_DIR}/t1_freesurfer_brain_input.mgz"
  local source_brain="${T1_FS_BRAIN}"
  [[ -f "${source_brain}" ]] || source_brain="${T1_BRAIN}"
  [[ -f "${source_brain}" ]] || die "Missing FreeSurfer brain volume: ${source_brain}"
  [[ -f "${SURFER_ORIG}" ]] || die "Cannot build FreeSurfer brainmask before orig.mgz exists"

  mkdir -p "${SURFER_SUBJECT_DIR}/mri"
  mri_convert "${source_brain}" "${tmp_brain}" >"${PHASE1_ANAT_STEP2_DIR}/mri_convert_brainmask.log" 2>&1
  mri_vol2vol \
    --mov "${tmp_brain}" \
    --targ "${SURFER_ORIG}" \
    --regheader \
    --interp trilinear \
    --o "${SURFER_BRAINMASK_AUTO}" >"${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_brainmask.log" 2>&1
  cp -f "${SURFER_BRAINMASK_AUTO}" "${SURFER_BRAINMASK}"
}

write_dataset_specific_expert_opts() {
  [[ "${SURFER_TYPE}" == "free" ]] || {
    rm -f "${FS_EXPERT_OPTS}"
    return 0
  }
  if [[ -n "${PHASE1_FREESURFER_CORTEX_LABEL_ARGS:-}" ]]; then
    printf 'CortexLabel %s\n' "${PHASE1_FREESURFER_CORTEX_LABEL_ARGS}" >"${FS_EXPERT_OPTS}"
  else
    rm -f "${FS_EXPERT_OPTS}"
  fi
}

step_manifest_value() {
  local manifest_path="$1"
  local manifest_key="$2"
  [[ -f "$manifest_path" ]] || return 0
  awk -F '\t' -v target="$manifest_key" '$1 == target { print $2; exit }' "$manifest_path"
}

step2_requires_config_refresh() {
  local manifest_hires=""
  local manifest_fastsurfer_vox_size=""
  local manifest_t1_resample_voxel_size=""
  local manifest_surfer_use_t2=""
  local current_t1_resample_voxel_size="${INIT_T1_RESAMPLE_VOXEL_SIZE:-1}"

  if [[ ! -f "${STEP2_MANIFEST}" ]]; then
    if [[ -d "${SURFER_SUBJECT_DIR}" ]] && { [[ "${SURFER_HIRES_EFFECTIVE:-0}" == "1" ]] || [[ "${INIT_T1_RESAMPLE_ENABLE:-0}" == "1" ]] || [[ "${SURFER_USE_T2:-0}" == "1" ]] || { [[ "${SURFER_TYPE}" == "fast" && "${PHASE1_FASTSURFER_VOX_SIZE:-min}" != "min" ]]; }; }; then
      return 0
    fi
    return 1
  fi

  manifest_hires="$(step_manifest_value "${STEP2_MANIFEST}" "surfer_hires")"
  if [[ "${manifest_hires:-0}" != "${SURFER_HIRES_EFFECTIVE:-0}" ]]; then
    return 0
  fi

  if [[ "${SURFER_TYPE}" == "fast" && "${PHASE1_FASTSURFER_VOX_SIZE:-min}" != "min" ]]; then
    manifest_fastsurfer_vox_size="$(step_manifest_value "${STEP2_MANIFEST}" "fastsurfer_vox_size")"
    if [[ "${manifest_fastsurfer_vox_size}" != "${PHASE1_FASTSURFER_VOX_SIZE:-min}" ]]; then
      return 0
    fi
  fi

  if [[ "${INIT_T1_RESAMPLE_ENABLE:-0}" == "1" ]]; then
    manifest_t1_resample_voxel_size="$(step_manifest_value "${STEP2_MANIFEST}" "t1_resample_voxel_size_mm")"
    if [[ "${manifest_t1_resample_voxel_size}" != "${current_t1_resample_voxel_size}" ]]; then
      return 0
    fi
  fi

  manifest_surfer_use_t2="$(step_manifest_value "${STEP2_MANIFEST}" "surfer_use_t2")"
  if [[ "${manifest_surfer_use_t2:-0}" != "${SURFER_USE_T2:-0}" ]]; then
    return 0
  fi

  return 1
}

reset_surfer_subject() {
  local reason="$1"
  local preserve_engine_log="${2:-0}"
  log "[phase1_anat] Step2 resetting ${SURFER_LABEL} subject for ${SUBJECT_ID}: ${reason}"
  rm -rf "${SURFER_SUBJECT_DIR}"
  rm -f "${APARC_ASEG}" \
    "${SURFER_DONE}" \
    "${STEP2_MANIFEST}" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_aparc2aseg.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_aparc_native.log" \
    "${PHASE1_ANAT_STEP2_DIR}/recon-all-init.log"
  if [[ "${preserve_engine_log}" != "1" ]]; then
    rm -f "${SURFER_ENGINE_LOG}"
  fi
}

write_surfer_done() {
  cat > "${SURFER_DONE}" <<EOF
surfer_type	${SURFER_TYPE}
surfer_label	${SURFER_LABEL}
subject_id	${SUBJECT_ID}
subject_dir	${SURFER_SUBJECT_DIR}
EOF
}

run_freesurfer() {
  local fs_xmask="${SURFER_T1_FS_XMASK_EFFECTIVE}"
  local recon_args=()
  local t2_coreg="${SURFER_T2_INPUT_EFFECTIVE}"
  local t1_input="${SURFER_T1_INPUT_EFFECTIVE}"
  local attempt_log="${PHASE1_ANAT_STEP2_DIR}/recon-all.attempt${SURFER_RETRY_ATTEMPT}.log"
  local recon_status=0
  [[ -f "${fs_xmask}" ]] || fs_xmask="${SURFER_T1_MASK_EFFECTIVE}"
  SURFER_ENGINE_LOG_CURRENT="${attempt_log}"
  : > "${attempt_log}"
  if [[ "${SURFER_HIRES_EFFECTIVE:-0}" == "1" ]]; then
    recon_args+=(-hires)
    log "[phase1_anat] Step2 enabling FreeSurfer -hires (${SURFER_HIRES_REASON})"
  fi
  if [[ "${SURFER_USE_T2_EFFECTIVE}" == "1" && -f "${t2_coreg}" ]]; then
    recon_args+=(-T2 "${t2_coreg}" -T2pial)
    log "[phase1_anat] Step2 injecting T2 volume into FreeSurfer for precise pial placement"
  fi
  if [[ -f "${FS_EXPERT_OPTS}" ]]; then
    recon_args+=(-expert "${FS_EXPERT_OPTS}" -xopts-overwrite)
  fi
  if [[ "${PHASE1_FREESURFER_NO_V8:-0}" == "1" ]]; then
    # Some dataset configs require the classic external-skullstrip path because
    # FreeSurfer 8 v8 defaults inject synthstrip/synthseg/synthmorph steps.
    recon_args+=(-no-v8)
  fi
  {
    printf '===== %s FreeSurfer attempt %s/%s for %s (use_t2=%s, hires=%s) =====\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" \
      "${SURFER_RETRY_ATTEMPT}" \
      "$(( SURFER_RETRY_MAX + 1 ))" \
      "${SUBJECT_ID}" \
      "${SURFER_USE_T2_EFFECTIVE}" \
      "${SURFER_HIRES_EFFECTIVE:-0}"
    if [[ -f "${SURFER_SUBJECT_DIR}/mri/orig/001.mgz" ]]; then
      recon-all -s "${SUBJECT_ID}" -all -noskullstrip -xmask "${fs_xmask}" -openmp "${NTHREADS}" "${recon_args[@]}"
    else
      recon-all -i "${t1_input}" -s "${SUBJECT_ID}" -all -noskullstrip -xmask "${fs_xmask}" -openmp "${NTHREADS}" "${recon_args[@]}"
    fi
  } >>"${attempt_log}" 2>&1
  recon_status=$?
  cat "${attempt_log}" >>"${SURFER_ENGINE_LOG}"
  return "${recon_status}"
}

run_freesurfer_with_retries() {
  local recon_status=1
  local retry_count=0
  local current_log=""
  : > "${SURFER_ENGINE_LOG}"

  while true; do
    SURFER_RETRY_ATTEMPT="$(( retry_count + 1 ))"
    prepare_freesurfer_hires_inputs_if_needed
    set +e
    run_freesurfer
    recon_status=$?
    set -e
    (( recon_status == 0 )) && return 0

    current_log="${SURFER_ENGINE_LOG_CURRENT}"
    if [[ -f "${SURFER_ORIG}" ]] && [[ -f "${current_log}" ]] && grep -q "could not open mask volume brainmask.mgz" "${current_log}"; then
      retry_count=$(( retry_count + 1 ))
      if (( retry_count > SURFER_RETRY_MAX )); then
        break
      fi
      log "[phase1_anat] Step2 retry ${retry_count}/${SURFER_RETRY_MAX} after missing FreeSurfer brainmask for ${SUBJECT_ID}"
      ensure_freesurfer_brainmask
      rm -f "${FS_DONE}" "${SURFER_DONE}"
      continue
    fi

    if freesurfer_t2_pial_refine_segfault; then
      retry_count=$(( retry_count + 1 ))
      if (( retry_count > SURFER_RETRY_MAX )); then
        break
      fi
      log "[phase1_anat] Step2 retry ${retry_count}/${SURFER_RETRY_MAX} after FreeSurfer T2 pial refinement crash for ${SUBJECT_ID}; disabling T2"
      SURFER_USE_T2_EFFECTIVE="0"
      SURFER_T2_INPUT_EFFECTIVE=""
      reset_surfer_subject "t2 pial refinement crashed" 1
      continue
    fi

    break
  done

  return "${recon_status}"
}

run_fastsurfer() {
  local fastsurfer_t1="${BIDS_T1_INPUT}"
  [[ -f "${fastsurfer_t1}" ]] || fastsurfer_t1="${T1_NATIVE_INPUT}"
  [[ -f "${fastsurfer_t1}" ]] || die "Missing FastSurfer T1 input: ${BIDS_T1_INPUT}"
  local fastsurfer_label_cortex_args="${PHASE1_FASTSURFER_LABEL_CORTEX_ARGS:-}"
  local fastsurfer_vox_size="${PHASE1_FASTSURFER_VOX_SIZE:-min}"
  local fastsurfer_args=()
  export MPLCONFIGDIR="${MPLCONFIGDIR:-/tmp/mpl_fastsurfer}"
  mkdir -p "${MPLCONFIGDIR}"
  export CNS_FASTSURFER_LABEL_CORTEX_ARGS="${fastsurfer_label_cortex_args}"
  export CNS_FASTSURFER_FORCE_HIRES="${PHASE1_SURFER_HIRES:-0}"

  if fastsurfer_segmentation_ready && ! fastsurfer_engine_outputs_ready; then
    ensure_fastsurfer_surface_inputs
    fastsurfer_args=(
      --fs_license "${FS_LICENSE}" \
      --sid "${SUBJECT_ID}" \
      --sd "${SURFER_SUBJECTS_DIR}" \
      --threads "${NTHREADS}" \
      --ignore_fs_version \
      --surf_only \
      --edits \
      --py "${FASTSURFER_PYTHON}"
    )
    if [[ "${SURFER_USE_T2}" == "1" ]]; then
      fastsurfer_args+=(--t2 "${SURFER_T2_INPUT}" --reg_mode none)
    fi
    if [[ "$fastsurfer_vox_size" != "min" ]]; then
      fastsurfer_args+=(--vox_size "$fastsurfer_vox_size")
    fi
    bash "${FASTSURFER_HOME}/run_fastsurfer.sh" "${fastsurfer_args[@]}" >"${SURFER_ENGINE_LOG}" 2>&1
  else
    fastsurfer_args=(
      --fs_license "${FS_LICENSE}" \
      --sid "${SUBJECT_ID}" \
      --sd "${SURFER_SUBJECTS_DIR}" \
      --t1 "${fastsurfer_t1}" \
      --threads "${NTHREADS}" \
      --device "${FASTSURFER_DEVICE:-cpu}" \
      --viewagg_device "${FASTSURFER_VIEWAGG_DEVICE:-cpu}" \
      --ignore_fs_version \
      --parallel \
      --py "${FASTSURFER_PYTHON}"
    )
    if [[ "${SURFER_USE_T2}" == "1" ]]; then
      fastsurfer_args+=(--t2 "${SURFER_T2_INPUT}" --reg_mode none)
    fi
    if [[ "$fastsurfer_vox_size" != "min" ]]; then
      fastsurfer_args+=(--vox_size "$fastsurfer_vox_size")
    fi
    bash "${FASTSURFER_HOME}/run_fastsurfer.sh" "${fastsurfer_args[@]}" >"${SURFER_ENGINE_LOG}" 2>&1
  fi
}

# 输出当前 step 的开始日志。
log "[phase1_anat] Step2 ${SURFER_LABEL} recon for ${SUBJECT_ID}"

# 在进入 recon-all 前先写出 dataset 专属 expert 选项。
write_dataset_specific_expert_opts

if step2_requires_config_refresh; then
  reset_surfer_subject "config changed"
fi

# 如果当前 step 的主要结果都已存在且 aparc+aseg 已处于 T1 native space，则直接跳过。
# 这里要兼容旧版 FreeSurfer 结果：历史产物可能还没有新的 surfer.done，但关键输出已经齐全。
if [[ -f "${STEP2_MANIFEST}" ]] && surfer_surfaces_ready && surfer_core_volumes_ready && step2_native_outputs_ready && ! freesurfer_uses_v8_defaults; then
  [[ -f "${SURFER_DONE}" ]] || write_surfer_done
  log "[phase1_anat] Step2 already done for ${SUBJECT_ID}"
  exit 0
fi

# 兼容历史 FastSurfer 结果：如果引擎级产物已经齐全，只差外层导出，不要重复跑 FastSurfer。
if [[ "${SURFER_TYPE}" == "fast" ]] && fastsurfer_engine_outputs_ready; then
  ensure_fastsurfer_surface_inputs
  ensure_fastsurfer_aparc_aseg
  repair_fastsurfer_desikan_aparc
fi

# 兼容历史 FreeSurfer 结果：如果 recon-all 已经完整结束、只是在 step2 外层收尾阶段中断，
# 则直接复用现有 subject 目录继续导出，不要再重跑 recon-all。
if freesurfer_engine_outputs_ready; then
  [[ -f "${SURFER_DONE}" ]] || write_surfer_done
fi

# 如果上次 FreeSurfer 中断留下了死锁文件，则在确认进程已不存在后清理锁文件。
if [[ "${SURFER_TYPE}" == "free" && -f "${SURFER_SUBJECT_DIR}/scripts/IsRunning.lh+rh" && ! -f "${FS_DONE}" ]]; then
  fs_pid="$(awk '/^PROCESSID/ {print $2}' "${SURFER_SUBJECT_DIR}/scripts/IsRunning.lh+rh" | head -n 1 || true)"
  if [[ -z "${fs_pid}" ]] || ! kill -0 "${fs_pid}" 2>/dev/null; then
    rm -f "${SURFER_SUBJECT_DIR}/scripts/IsRunning.lh+rh"
  fi
fi

# 如果上次 FreeSurfer 已经失败，或者留下了假的 done 但关键中间结果并不完整，则清空坏掉的 subject 后重新开始。
if [[ "${SURFER_TYPE}" == "free" ]] && { [[ -f "${FS_ERROR}" ]] || [[ -f "${FS_DONE}" ]] || [[ -f "${SURFER_DONE}" ]] || freesurfer_uses_v8_defaults; } && { ! surfer_surfaces_ready || ! surfer_core_volumes_ready || freesurfer_uses_v8_defaults; }; then
  log "[phase1_anat] Step2 resetting incomplete ${SURFER_LABEL} subject for ${SUBJECT_ID}"
  rm -rf "${SURFER_SUBJECT_DIR}"
  rm -f "${APARC_ASEG}" \
    "${SURFER_DONE}" \
    "${SURFER_ENGINE_LOG}" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_aparc2aseg.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/recon-all-init.log"
fi

# FastSurfer 如果落下了假的 done 标记，但引擎级产物并未真正齐全，先去掉完成标记，避免后续误判。
if [[ "${SURFER_TYPE}" == "fast" && -f "${SURFER_DONE}" ]] && ! fastsurfer_engine_outputs_ready; then
  rm -f "${SURFER_DONE}"
fi

# FastSurfer 如果已经留下了完整 segmentation 但表面还没生成，则保留分割结果，转入 surf_only 续跑。
if [[ "${SURFER_TYPE}" == "fast" ]] && [[ -d "${SURFER_SUBJECT_DIR}" ]] && ! fastsurfer_engine_outputs_ready && fastsurfer_segmentation_ready; then
  ensure_fastsurfer_surface_inputs
fi

# FastSurfer 如果是半残缺目录且 segmentation 也不完整，则直接清空后从头来，避免反复踩 existing subject directory。
if [[ "${SURFER_TYPE}" == "fast" ]] && [[ -d "${SURFER_SUBJECT_DIR}" ]] && ! fastsurfer_engine_outputs_ready && ! fastsurfer_segmentation_ready; then
  log "[phase1_anat] Step2 resetting incomplete FastSurfer subject for ${SUBJECT_ID}"
  rm -rf "${SURFER_SUBJECT_DIR}"
  rm -f "${APARC_ASEG}" "${SURFER_DONE}" "${SURFER_ENGINE_LOG}"
fi

# 如果上次留下了假的 done 标记但表面没有真正生成，则清掉 done 并继续修复性续跑。
if [[ -f "${FS_DONE}" ]] && { { [[ "${SURFER_TYPE}" == "fast" ]] && ! fastsurfer_engine_outputs_ready; } || { [[ "${SURFER_TYPE}" != "fast" ]] && ! surfer_surfaces_ready; }; }; then
  rm -f "${FS_DONE}" "${SURFER_DONE}"
fi

# 用选定的 surfer 引擎执行表面重建。
if [[ ! -f "${SURFER_DONE}" ]] || ! surfer_surfaces_ready; then
  if [[ "${SURFER_TYPE}" == "fast" ]] && fastsurfer_engine_outputs_ready; then
    :
  else
    set +e
    if [[ "${SURFER_TYPE}" == "free" ]]; then
      run_freesurfer_with_retries
    else
      run_fastsurfer
    fi
    recon_status=$?
    set -e

    if (( recon_status != 0 )) && [[ "${SURFER_TYPE}" == "fast" ]] && fastsurfer_recoverable_segstats_failure; then
      log "[phase1_anat] Step2 detected recoverable FastSurfer segstats failure for ${SUBJECT_ID}, reusing completed surfaces and mapped aparc+aseg"
      ensure_fastsurfer_surface_inputs
      ensure_fastsurfer_aparc_aseg
      recon_status=0
    fi

    (( recon_status == 0 )) || die "${SURFER_LABEL} recon failed: ${PHASE1_ANAT_STEP2_DIR}"
  fi
fi

# 在导出 aparc+aseg 前再次确认关键表面已经生成。
if [[ "${SURFER_TYPE}" == "fast" ]]; then
  fastsurfer_surfaces_ready || die "${SURFER_LABEL} surfaces missing after recon: ${SURFER_SUBJECT_DIR}/surf"
else
  surfer_surfaces_ready || die "${SURFER_LABEL} surfaces missing after recon: ${SURFER_SUBJECT_DIR}/surf"
fi
surfer_core_volumes_ready || die "${SURFER_LABEL} core volumes missing after recon: ${SURFER_SUBJECT_DIR}/mri"
if [[ "${SURFER_TYPE}" == "fast" ]]; then
  ensure_fastsurfer_aparc_aseg
  repair_fastsurfer_desikan_aparc
fi

# 导出体素版 aparc+aseg，并强制回到原始 T1 native space。
if [[ ! -f "${SURFER_APARC_ASEG_MGZ}" && "${SURFER_TYPE}" == "free" ]]; then
  mri_aparc2aseg --s "${SUBJECT_ID}" --annot aparc --o "${SURFER_APARC_ASEG_MGZ}" >"${PHASE1_ANAT_STEP2_DIR}/mri_aparc2aseg.log" 2>&1
fi

[[ -f "${SURFER_APARC_ASEG_MGZ}" ]] || die "Missing aparc+aseg from ${SURFER_LABEL}: ${SURFER_APARC_ASEG_MGZ}"

if ! step2_native_outputs_ready; then
  mri_vol2vol \
    --mov "${SURFER_APARC_ASEG_MGZ}" \
    --targ "${T1_NATIVE_INPUT}" \
    --regheader \
    --interp nearest \
    --o "${APARC_ASEG}" >"${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_aparc_native.log" 2>&1
fi

if fastsurfer_desikan_repair_enabled; then
  fastsurfer_desikan_labels_ready_in_volume "${APARC_ASEG}" || die "FastSurfer native aparc+aseg still missing Desikan cortical labels after export: ${APARC_ASEG}"
fi

write_surfer_done

# 写出当前 step 的输出清单。
cat > "${STEP2_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
surfer_type	${SURFER_TYPE}
surfer_label	${SURFER_LABEL}
bids_t1_input	${BIDS_T1_INPUT}
t1_native_input	${T1_NATIVE_INPUT}
t1_brain	${T1_BRAIN}
t1_brain_mask	${T1_MASK}
t1_freesurfer_xmask	${T1_FS_XMASK}
t1_freesurfer_brain	${T1_FS_BRAIN}
surfer_subjects_dir	${SURFER_SUBJECTS_DIR}
surfer_subject_dir	${SURFER_SUBJECT_DIR}
surfer_engine_log	${SURFER_ENGINE_LOG}
recon_all_args	$( [[ "${SURFER_TYPE}" == "free" ]] && echo "-i ${SURFER_T1_INPUT_EFFECTIVE} -all -noskullstrip -xmask ${SURFER_T1_FS_XMASK_EFFECTIVE} -openmp ${NTHREADS}$( [[ "${SURFER_HIRES_EFFECTIVE:-0}" == "1" ]] && printf ' -hires' )$( [[ "${SURFER_USE_T2_EFFECTIVE}" == "1" ]] && printf ' -T2 %s -T2pial' "${SURFER_T2_INPUT_EFFECTIVE}" )$( [[ "${PHASE1_FREESURFER_NO_V8:-0}" == "1" ]] && printf ' -no-v8' )" || echo "run_fastsurfer.sh --sid ${SUBJECT_ID} --sd ${SURFER_SUBJECTS_DIR} --t1 ${BIDS_T1_INPUT} --threads ${NTHREADS} --device ${FASTSURFER_DEVICE:-cpu} --viewagg_device ${FASTSURFER_VIEWAGG_DEVICE:-cpu} --vox_size ${PHASE1_FASTSURFER_VOX_SIZE:-min} --ignore_fs_version$( [[ "${SURFER_USE_T2}" == "1" ]] && printf ' --t2 %s --reg_mode none' "${SURFER_T2_INPUT}" )" )
surfer_hires	${SURFER_HIRES_EFFECTIVE:-0}
surfer_hires_reason	${SURFER_HIRES_REASON}
surfer_use_t2	${SURFER_USE_T2}
surfer_use_t2_effective	${SURFER_USE_T2_EFFECTIVE}
surfer_t2_input	${SURFER_T2_INPUT}
surfer_t1_input_effective	${SURFER_T1_INPUT_EFFECTIVE}
surfer_t2_input_effective	${SURFER_T2_INPUT_EFFECTIVE}
surfer_xmask_effective	${SURFER_T1_FS_XMASK_EFFECTIVE}
surfer_hires_input_crop_applied	${SURFER_HIRES_INPUT_CROP_APPLIED}
surfer_hires_input_crop_bounds	${SURFER_HIRES_INPUT_CROP_BOUNDS}
fastsurfer_vox_size	${PHASE1_FASTSURFER_VOX_SIZE:-min}
fastsurfer_desikan_repair_enabled	${PHASE1_FASTSURFER_DESIKAN_REPAIR_ENABLE:-1}
t1_resample_voxel_size_mm	${INIT_T1_RESAMPLE_VOXEL_SIZE:-1}
recon_all_expert_opts	${FS_EXPERT_OPTS}
freesurfer_cortex_label_args	$( [[ "${SURFER_TYPE}" == "free" ]] && echo "${PHASE1_FREESURFER_CORTEX_LABEL_ARGS:-}" || echo "" )
fastsurfer_label_cortex_args	$( [[ "${SURFER_TYPE}" == "fast" ]] && echo "${PHASE1_FASTSURFER_LABEL_CORTEX_ARGS:-}" || echo "" )
brainmask_mgz	${SURFER_BRAINMASK}
aparc_aseg	${APARC_ASEG}
EOF

# 把当前 step 的关键体素结果链接到 stepview，便于直接核对。
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 2 1 "surfer_input_t1" "${T1_NATIVE_INPUT}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 2 2 "surfer_aux_mask" "${T1_FS_XMASK}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 2 3 "aparc_aseg" "${APARC_ASEG}"
if [[ "${SURFER_USE_T2}" == "1" ]]; then
  link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 2 4 "surfer_input_t2" "${SURFER_T2_INPUT}"
fi
