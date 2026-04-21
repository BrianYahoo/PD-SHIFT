#!/usr/bin/env bash
set -euo pipefail

STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

load_config
setup_tools_env

STEP8_MANIFEST="${PHASE1_ANAT_STEP8_DIR}/manifest.tsv"
STEP8_LOG_DIR="${PHASE1_ANAT_STEP8_DIR}/logs"
SIMNIBS_ROOT_DIR="${PHASE1_ANAT_STEP8_DIR}/simnibs"
SIMNIBS_SUBJECT_TAG="${SUBJECT_ID//-/_}_simnibs"
SIMNIBS_M2M_DIR="${SIMNIBS_ROOT_DIR}/m2m_${SIMNIBS_SUBJECT_TAG}"
SIMNIBS_HEAD_MSH="${SIMNIBS_M2M_DIR}/${SIMNIBS_SUBJECT_TAG}.msh"

T1_N4="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
T2_COREG_T1="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
HYBRID_LABELS="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"
SURFER_SUBJECT_DIR="${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}"

STEP8_USE_T2="0"
if [[ "${PHASE1_EEG_USE_T2:-0}" == "1" && -f "${T2_COREG_T1}" ]]; then
  STEP8_USE_T2="1"
fi

CAP_SOURCE_KEY="${PHASE1_EEG_CAP_SOURCE:-standard_10_10}"
LF_VARIANT_DIR="${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${CAP_SOURCE_KEY}"
LF_LOG_DIR="${LF_VARIANT_DIR}/logs"
LF_CAP_CSV="${LF_VARIANT_DIR}/eeg_cap.csv"
LF_QC_TSV="${LF_VARIANT_DIR}/${SUBJECT_ID}_EEG_Leadfield_qc.tsv"
LF_68_CSV="${LF_VARIANT_DIR}/${SUBJECT_ID}_EEG_Leadfield_${PHASE1_EEG_ELECTRODE_COUNT}x68.csv"
LF_88_CSV="${LF_VARIANT_DIR}/${SUBJECT_ID}_EEG_Leadfield_${PHASE1_EEG_ELECTRODE_COUNT}x88.csv"
LF_FEM_DIR="${LF_VARIANT_DIR}/fem"
LF_HDF5=""

mkdir -p "${STEP8_LOG_DIR}" "${SIMNIBS_ROOT_DIR}" "${LF_VARIANT_DIR}" "${LF_LOG_DIR}" "${LF_FEM_DIR}"

log "[phase1_anat] Step8 EEG leadfield for ${SUBJECT_ID}"

write_step8_manifest() {
  local status="$1"
  local leadfield_hdf5="${2:-}"
  cat > "${STEP8_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
status	${status}
eeg_leadfield_enable	${PHASE1_EEG_LEADFIELD_ENABLE:-0}
simnibs_subject_tag	${SIMNIBS_SUBJECT_TAG}
simnibs_root_dir	${SIMNIBS_ROOT_DIR}
simnibs_m2m_dir	${SIMNIBS_M2M_DIR}
simnibs_head_mesh	${SIMNIBS_HEAD_MSH}
leadfield_variant_dir	${LF_VARIANT_DIR}
leadfield_cap_source	${CAP_SOURCE_KEY}
leadfield_cap_csv	${LF_CAP_CSV}
leadfield_reference_electrode	${PHASE1_EEG_REFERENCE_ELECTRODE}
leadfield_electrode_count	${PHASE1_EEG_ELECTRODE_COUNT}
leadfield_field	${PHASE1_EEG_LEADFIELD_FIELD}
leadfield_subsampling	${PHASE1_EEG_TDCS_SUBSAMPLING}
leadfield_hdf5	${leadfield_hdf5}
leadfield_qc_tsv	${LF_QC_TSV}
leadfield_68_csv	${LF_68_CSV}
leadfield_88_csv	${LF_88_CSV}
leadfield_use_t2	${STEP8_USE_T2}
custom_cap_csv	${PHASE1_EEG_CUSTOM_CAP_CSV:-}
simnibs_python	${SIMNIBS_PYTHON_BIN:-}
simnibs_charm_cmd	${SIMNIBS_CHARM_CMD}
simnibs_prepare_tdcs_leadfield_cmd	${SIMNIBS_PREPARE_TDCS_LEADFIELD_CMD}
EOF
}

resolve_leadfield_hdf5() {
  find "${LF_FEM_DIR}" -maxdepth 1 -type f -name '*leadfield*.hdf5' | sort | head -n 1
}

step8_outputs_ready() {
  local resolved_hdf5=""
  [[ -f "${STEP8_MANIFEST}" && -f "${LF_CAP_CSV}" && -f "${LF_QC_TSV}" && -f "${LF_68_CSV}" && -f "${LF_88_CSV}" ]] || return 1
  resolved_hdf5="$(resolve_leadfield_hdf5)"
  [[ -n "${resolved_hdf5}" && -f "${resolved_hdf5}" ]] || return 1
}

if [[ "${PHASE1_EEG_LEADFIELD_ENABLE:-0}" != "1" ]]; then
  write_step8_manifest "disabled"
  log "[phase1_anat] Step8 disabled by config for ${SUBJECT_ID}"
  exit 0
fi

[[ -f "${T1_N4}" ]] || die "Missing T1 for Step8: ${T1_N4}"
[[ -f "${APARC_ASEG}" ]] || die "Missing aparc+aseg for Step8: ${APARC_ASEG}"
[[ -f "${HYBRID_LABELS}" ]] || die "Missing hybrid labels TSV for Step8: ${HYBRID_LABELS}"

if step8_outputs_ready; then
  write_step8_manifest "done" "$(resolve_leadfield_hdf5)"
  log "[phase1_anat] Step8 already done for ${SUBJECT_ID}"
  exit 0
fi

setup_simnibs_env

run_charm() {
  local force_affine="${PHASE1_EEG_CHARM_FORCE_AFFINE:-auto}"
  local -a charm_args=("${SIMNIBS_SUBJECT_TAG}" "${T1_N4}")
  local -a retry_args=("${SIMNIBS_SUBJECT_TAG}" "${T1_N4}")
  if [[ "${STEP8_USE_T2}" == "1" ]]; then
    charm_args+=("${T2_COREG_T1}")
    retry_args+=("${T2_COREG_T1}")
  fi
  if [[ "${PHASE1_EEG_CHARM_USE_FS_DIR:-1}" == "1" && -d "${SURFER_SUBJECT_DIR}" ]]; then
    charm_args+=(--fs-dir "${SURFER_SUBJECT_DIR}")
    retry_args+=(--fs-dir "${SURFER_SUBJECT_DIR}")
  fi
  if [[ -d "${SIMNIBS_M2M_DIR}" && ! -f "${SIMNIBS_HEAD_MSH}" ]]; then
    charm_args+=(--forcerun)
    retry_args+=(--forcerun)
  fi
  case "${force_affine}" in
    qform) charm_args+=(--forceqform) ;;
    sform) charm_args+=(--forcesform) ;;
    auto|none|"") ;;
    *) die "Unsupported PHASE1_EEG_CHARM_FORCE_AFFINE=${force_affine}" ;;
  esac

  if (
    cd "${SIMNIBS_ROOT_DIR}"
    "${SIMNIBS_CHARM_CMD}" "${charm_args[@]}"
  ) >"${STEP8_LOG_DIR}/charm.log" 2>&1; then
    return 0
  fi

  if [[ "${force_affine}" == "auto" ]] && grep -q "qform and sform matrices do not match" "${STEP8_LOG_DIR}/charm.log"; then
    log "[phase1_anat] Step8 CHARM detected qform/sform mismatch for ${SUBJECT_ID}, retrying with --forceqform"
    (
      cd "${SIMNIBS_ROOT_DIR}"
      "${SIMNIBS_CHARM_CMD}" "${retry_args[@]}" --forceqform
    ) >"${STEP8_LOG_DIR}/charm.log" 2>&1
    return 0
  fi

  return 1
}

if [[ ! -d "${SIMNIBS_M2M_DIR}" || ! -f "${SIMNIBS_HEAD_MSH}" ]]; then
  run_charm
fi

[[ -d "${SIMNIBS_M2M_DIR}" ]] || die "SimNIBS CHARM did not create m2m directory: ${SIMNIBS_M2M_DIR}"
[[ -f "${SIMNIBS_HEAD_MSH}" ]] || die "SimNIBS CHARM did not create head mesh: ${SIMNIBS_HEAD_MSH}"

STANDARD_1010_CSV="${SIMNIBS_M2M_DIR}/eeg_positions/EEG10-10_UI_Jurak_2007.csv"
"${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step8/prepare_eeg_cap.py" \
  --mode "${CAP_SOURCE_KEY}" \
  --electrode-count "${PHASE1_EEG_ELECTRODE_COUNT}" \
  --reference-electrode "${PHASE1_EEG_REFERENCE_ELECTRODE}" \
  --standard-1010-csv "${STANDARD_1010_CSV}" \
  --custom-csv "${PHASE1_EEG_CUSTOM_CAP_CSV:-}" \
  --output-csv "${LF_CAP_CSV}" >"${LF_LOG_DIR}/prepare_cap.log" 2>&1

LF_HDF5="$(resolve_leadfield_hdf5)"
if [[ -z "${LF_HDF5}" || ! -f "${LF_HDF5}" ]]; then
  prepare_args=("${SIMNIBS_SUBJECT_TAG}" "${LF_CAP_CSV}" -o "${LF_FEM_DIR}")
  if [[ "${PHASE1_EEG_TDCS_SUBSAMPLING:-0}" =~ ^[0-9]+$ ]] && (( PHASE1_EEG_TDCS_SUBSAMPLING > 0 )); then
    prepare_args+=(-s "${PHASE1_EEG_TDCS_SUBSAMPLING}")
  fi
  (
    cd "${SIMNIBS_ROOT_DIR}"
    "${SIMNIBS_PREPARE_TDCS_LEADFIELD_CMD}" "${prepare_args[@]}"
  ) >"${LF_LOG_DIR}/prepare_tdcs_leadfield.log" 2>&1
  LF_HDF5="$(resolve_leadfield_hdf5)"
fi

[[ -n "${LF_HDF5}" && -f "${LF_HDF5}" ]] || die "Failed to locate SimNIBS leadfield HDF5 under ${LF_FEM_DIR}"

"${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step8/build_eeg_leadfield_matrix.py" \
  --leadfield-hdf5 "${LF_HDF5}" \
  --atlas "${APARC_ASEG}" \
  --labels-tsv "${HYBRID_LABELS}" \
  --cap-csv "${LF_CAP_CSV}" \
  --reference-electrode "${PHASE1_EEG_REFERENCE_ELECTRODE}" \
  --field "${PHASE1_EEG_LEADFIELD_FIELD}" \
  --output-68 "${LF_68_CSV}" \
  --output-88 "${LF_88_CSV}" \
  --output-qc "${LF_QC_TSV}" >"${LF_LOG_DIR}/build_matrix.log" 2>&1

[[ -f "${LF_68_CSV}" && -f "${LF_88_CSV}" && -f "${LF_QC_TSV}" ]] || die "Step8 outputs are incomplete for ${SUBJECT_ID}"

write_step8_manifest "done" "${LF_HDF5}"
log "[phase1_anat] Step8 done for ${SUBJECT_ID}"
