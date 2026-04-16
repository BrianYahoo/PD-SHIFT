#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PIPELINE_ROOT}/config"
UTILS_DIR="${PIPELINE_ROOT}/utils"
if [[ -n "${PYTHONPATH:-}" ]]; then
  export PYTHONPATH="${UTILS_DIR}:${PYTHONPATH}"
else
  export PYTHONPATH="${UTILS_DIR}"
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "Command not found: $cmd"
}

nifti_is_readable() {
  local nifti_path="$1"
  local pybin="${PYTHON_BIN:-python3}"
  [[ -f "$nifti_path" ]] || return 1
  if [[ "$nifti_path" == *.gz ]]; then
    gzip -t "$nifti_path" >/dev/null 2>&1 || return 1
  fi
  "$pybin" - "$nifti_path" <<'PY' >/dev/null 2>&1
import sys
import nibabel as nib

path = sys.argv[1]
img = nib.load(path)
_ = img.shape
PY
}

pick_first_existing_dir() {
  local d
  for d in "$@"; do
    if [[ -n "$d" && -d "$d" ]]; then
      echo "$d"
      return 0
    fi
  done
  return 0
}

pick_largest_matching_nifti() {
  local src_dir="$1"
  local include_glob="${2:-*}"
  local exclude_glob="${3:-}"
  local best=""
  local best_size=-1
  local f b size

  while IFS= read -r f; do
    b="$(basename "$f")"
    [[ "$b" == $include_glob ]] || continue
    if [[ -n "$exclude_glob" && "$b" == $exclude_glob ]]; then
      continue
    fi
    size="$(stat -c '%s' "$f" 2>/dev/null || stat -f '%z' "$f" 2>/dev/null || echo 0)"
    if (( size > best_size )); then
      best_size="$size"
      best="$f"
    fi
  done < <(find "$src_dir" -maxdepth 1 -type f -name "*.nii.gz" | sort)

  if [[ -n "$best" ]]; then
    echo "$best"
  fi
}

infer_pe_from_name() {
  local src_name="$1"
  local default_pe="${2:-j}"
  local b
  b="$(basename "$src_name")"

  if [[ "$b" == *"_LR"* ]]; then
    echo "i-"
    return 0
  fi
  if [[ "$b" == *"_RL"* ]]; then
    echo "i"
    return 0
  fi
  if [[ "$b" == *"_AP"* ]]; then
    echo "j-"
    return 0
  fi
  if [[ "$b" == *"_PA"* ]]; then
    echo "j"
    return 0
  fi
  echo "$default_pe"
}

normalize_dataset_type() {
  local dataset_type="${1:-}"
  case "${dataset_type,,}" in
    hcp)
      echo "hcp"
      ;;
    parkinson)
      echo "parkinson"
      ;;
    *)
      die "Unsupported dataset: ${dataset_type}"
      ;;
  esac
}

normalize_surfer_type() {
  local surfer_type="${1:-}"
  case "${surfer_type,,}" in
    free|freesurfer)
      echo "free"
      ;;
    fast|fastsurfer)
      echo "fast"
      ;;
    *)
      die "Unsupported surfer type: ${surfer_type}"
      ;;
  esac
}

surfer_label() {
  local surfer_type="${1:-}"
  case "$(normalize_surfer_type "$surfer_type")" in
    free)
      echo "FreeSurfer"
      ;;
    fast)
      echo "FastSurfer"
      ;;
  esac
}

normalize_subject_key() {
  local subject_value="${1:-}"
  subject_value="${subject_value#sub-}"
  echo "$subject_value"
}

normalize_subject_id() {
  local subject_value="${1:-}"
  if [[ "$subject_value" == sub-* ]]; then
    echo "$subject_value"
  else
    echo "sub-${subject_value}"
  fi
}

load_dataset_config() {
  local requested_dataset="${1:-${PIPELINE_DATASET:-}}"

  [[ -f "${CONFIG_DIR}/pipeline.env" ]] || die "Missing config: ${CONFIG_DIR}/pipeline.env"
  # shellcheck disable=SC1090
  source "${CONFIG_DIR}/pipeline.env"
  requested_dataset="${requested_dataset:-${DATASET_TYPE:-}}"
  DATASET_TYPE="$(normalize_dataset_type "$requested_dataset")"
  SURFER_TYPE="$(normalize_surfer_type "${PIPELINE_SURFER:-${SURFER_TYPE:-free}}")"
  SURFER_LABEL="$(surfer_label "${SURFER_TYPE}")"

  if [[ -f "${CONFIG_DIR}/datasets/${DATASET_TYPE}.env" ]]; then
    # shellcheck disable=SC1090
    source "${CONFIG_DIR}/datasets/${DATASET_TYPE}.env"
  fi

  : "${DATASET_IMPORT_MODE:?Missing DATASET_IMPORT_MODE in dataset config}"
  : "${INIT_T1_RESAMPLE_ENABLE:=${INIT_T1_RESAMPLE_TO_1MM:-0}}"
  INIT_T1_RESAMPLE_TO_1MM="${INIT_T1_RESAMPLE_ENABLE}"
  : "${INIT_T1_RESAMPLE_VOXEL_SIZE:=1}"
  : "${INIT_T2_ENABLE:=0}"
  : "${INIT_T2_SOURCE_PATTERNS:=}"
  : "${INIT_T2_HCP_DIR_CANDIDATES:=T2w_SPC1;T2w_SPC2}"
  : "${INIT_T2_HCP_FILE_PATTERNS:=*T2w*.nii.gz}"
  : "${DEFAULT_FUNC_TR:=0.72}"
  : "${FUNC_REQUIRE_JSON_TR:=0}"
  : "${DEFAULT_TOTAL_READOUT_TIME:=0.05}"
  : "${PHASE1_BRAIN_EXTRACT_METHOD:=bet}"
  : "${PHASE1_SURFER_HIRES:=0}"
  : "${PHASE1_T2_COREG_ENABLE:=${INIT_T2_ENABLE}}"
  : "${PHASE1_T2_SURFER_ENABLE:=${PHASE1_T2_COREG_ENABLE}}"
  : "${PHASE1_T2_MULTICHANNEL_REG_ENABLE:=${PHASE1_T2_COREG_ENABLE}}"
  : "${PHASE1_SUBCORTICAL_MASK_ENABLE:=0}"
  : "${PHASE1_TISSUE_PROFILE_ENABLE:=${PHASE1_T2_COREG_ENABLE}}"
  : "${PHASE1_TISSUE_PROFILE_CIFTI_ENABLE:=${PHASE1_TISSUE_PROFILE_ENABLE}}"
  : "${PHASE1_TISSUE_PROFILE_FSLR_MESH_K:=32}"
  : "${PHASE1_TISSUE_PROFILE_HIGHRES_MESH_K:=164}"
  : "${PHASE1_SURFACE_PLOT_ENV:=osmesa}"
  : "${PHASE1_SURFACE_PLOT_MRI_PYTHON:=}"
  : "${PHASE1_SURFACE_PLOT_OSMESA_PYTHON:=/data/bryang/project/CNS/tools/surfplot_osmesa_env/bin/python}"
  : "${PHASE1_REG_AFFINE_ENABLE:=1}"
  : "${PHASE1_FREESURFER_NO_V8:=0}"
  : "${PHASE1_FREESURFER_V8_GUARD:=0}"
  : "${PHASE1_FREESURFER_CORTEX_LABEL_ARGS:=}"
  : "${PHASE1_FASTSURFER_LABEL_CORTEX_ARGS:=}"
  : "${PHASE1_FASTSURFER_VOX_SIZE:=min}"
  : "${FASTSURFER_USE_CUDA:=0}"
  : "${FASTSURFER_CUDA_AUTO_ASSIGN:=0}"
  : "${FASTSURFER_CUDA_DEVICES:=0,1,2,3,4,5,6,7}"
  : "${FASTSURFER_CUDA_SELECTION:=round_robin}"
  : "${FASTSURFER_CUDA_MAX_SELECTED_DEVICES:=5}"
  : "${FASTSURFER_CUDA_ENV_SCRIPT:=/data/bryang/project/CNS/tools/use_fastsurfer_cuda_env.sh}"
  : "${MNI_T2:=}"
  : "${MNI_SUBCORTICAL_MASK:=}"
  if [[ "${FASTSURFER_USE_CUDA}" == "1" ]]; then
    FASTSURFER_DEVICE="cuda"
    FASTSURFER_VIEWAGG_DEVICE="cuda"
  fi
}

list_dataset_subject_dirs() {
  local dataset_type="${1:-${PIPELINE_DATASET:-${DATASET_TYPE:-}}}"
  load_dataset_config "$dataset_type"
  find "$RAW_ROOT" -mindepth 1 -maxdepth 1 -type d | sort
}

list_dataset_subject_keys() {
  local subject_dir=""
  while IFS= read -r subject_dir; do
    [[ -n "$subject_dir" ]] || continue
    basename "$subject_dir"
  done < <(list_dataset_subject_dirs "${1:-${PIPELINE_DATASET:-${DATASET_TYPE:-}}}")
}

resolve_subject_dir() {
  local dataset_type="${1:-${PIPELINE_DATASET:-${DATASET_TYPE:-}}}"
  local subject_value="${2:-${PIPELINE_SUBJECT:-}}"
  local subject_key=""

  load_dataset_config "$dataset_type"
  subject_key="$(normalize_subject_key "$subject_value")"
  [[ -n "$subject_key" ]] || die "Missing subject"

  if [[ -d "${RAW_ROOT}/${subject_key}" ]]; then
    echo "${RAW_ROOT}/${subject_key}"
    return 0
  fi

  die "Subject not found in ${DATASET_TYPE}: ${subject_value}"
}

load_config() {
  local dataset_type="${1:-${PIPELINE_DATASET:-${DATASET_TYPE:-}}}"
  local subject_value="${2:-${PIPELINE_SUBJECT:-}}"

  load_dataset_config "$dataset_type"

  if [[ -n "${PIPELINE_SUBJECT_DIR:-}" ]]; then
    SUBJECT_DIR="${PIPELINE_SUBJECT_DIR}"
  else
    SUBJECT_DIR="$(resolve_subject_dir "$DATASET_TYPE" "$subject_value")"
  fi

  [[ -n "${SUBJECT_DIR:-}" ]] || die "SUBJECT_DIR missing"
  [[ -d "${SUBJECT_DIR}" ]] || die "SUBJECT_DIR does not exist: ${SUBJECT_DIR}"

  SUBJECT_KEY="$(basename "$SUBJECT_DIR")"
  SUBJECT_ID="$(normalize_subject_id "$SUBJECT_KEY")"
  DATASET_WORKSPACE_ROOT="${WORKSPACE_ROOT}"
  WORKSPACE_ROOT="${DATASET_WORKSPACE_ROOT}/${SURFER_LABEL}"
  SUBJECT_WORK_ROOT="${WORKSPACE_ROOT}/${SUBJECT_KEY}"
  SUBJECT_VIS_ROOT="${SUBJECT_WORK_ROOT}/visualization"
  BIDS_SUBJECT_DIR="${SUBJECT_WORK_ROOT}/bids/${SUBJECT_ID}"
  DERIV_ROOT="${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}"

  PHASES_ROOT="${DERIV_ROOT}/phases"

  PHASE0_INIT_DIR="${PHASES_ROOT}/phase0_init"
  PHASE0_INIT_STEP1_DIR="${PHASE0_INIT_DIR}/step1_bids_standardize"
  PHASE0_INIT_VIS_DIR="${SUBJECT_VIS_ROOT}/phase0_init"
  PHASE0_INIT_STEPVIEW_DIR="${PHASE0_INIT_VIS_DIR}/stepview"

  PHASE1_ANAT_DIR="${PHASES_ROOT}/phase1_anat"
  PHASE1_ANAT_STEP1_DIR="${PHASE1_ANAT_DIR}/step1_brain_extract"
  PHASE1_ANAT_STEP2_DIR="${PHASE1_ANAT_DIR}/step2_surfer_recon"
  PHASE1_ANAT_STEP3_DIR="${PHASE1_ANAT_DIR}/step3_subcortical_syn"
  PHASE1_ANAT_STEP4_DIR="${PHASE1_ANAT_DIR}/step4_warpdrive_review"
  PHASE1_ANAT_STEP5_DIR="${PHASE1_ANAT_DIR}/step5_save_inverse_warp"
  PHASE1_ANAT_STEP6_DIR="${PHASE1_ANAT_DIR}/step6_distal_inverse_fusion"
  PHASE1_ANAT_STEP7_DIR="${PHASE1_ANAT_DIR}/step7_t1t2_myelin"
  PHASE1_ANAT_VIS_DIR="${SUBJECT_VIS_ROOT}/phase1_anat"
  PHASE1_ANAT_STEPVIEW_DIR="${PHASE1_ANAT_VIS_DIR}/stepview"
  ATLAS_DIR="${PHASE1_ANAT_DIR}/atlas"

  PHASE2_FMRI_DIR="${PHASES_ROOT}/phase2_fmri"
  PHASE2_FMRI_VIS_DIR="${SUBJECT_VIS_ROOT}/phase2_fmri"
  PHASE2_FMRI_STEPVIEW_DIR="${PHASE2_FMRI_VIS_DIR}/stepview"
  FMRI_ROOT_DIR="${PHASE2_FMRI_DIR}"
  FMRI_DIR="${FMRI_ROOT_DIR}"

  PHASE3_DWI_DIR="${PHASES_ROOT}/phase3_dwi"
  PHASE3_DWI_VIS_DIR="${SUBJECT_VIS_ROOT}/phase3_dwi"
  PHASE3_DWI_STEPVIEW_DIR="${PHASE3_DWI_VIS_DIR}/stepview"
  DWI_DIR="${PHASE3_DWI_DIR}"

  PHASE4_SUMMARY_DIR="${PHASES_ROOT}/phase4_summary"
  FINAL_DIR="${PHASE4_SUMMARY_DIR}/final"
  REPORTS_DIR="${PHASE4_SUMMARY_DIR}/reports"
  COMPARE_DIR="${PHASE4_SUMMARY_DIR}/comparison"

  # 兼容旧变量名，后续逐步替换为 phase 变量。
  INIT_DIR="${PHASE0_INIT_DIR}"
  INIT_STEP0_DIR="${PHASE0_INIT_STEP1_DIR}"
  INIT_STEP1_DIR="${PHASE1_ANAT_STEP2_DIR}"

  mkdir -p \
    "${BIDS_SUBJECT_DIR}/anat" \
    "${BIDS_SUBJECT_DIR}/func" \
    "${BIDS_SUBJECT_DIR}/dwi" \
    "${SUBJECT_VIS_ROOT}" \
    "${PHASES_ROOT}" \
    "${PHASE0_INIT_STEP1_DIR}" \
    "${PHASE0_INIT_VIS_DIR}" \
    "${PHASE0_INIT_STEPVIEW_DIR}" \
    "${PHASE1_ANAT_STEP1_DIR}" \
    "${PHASE1_ANAT_STEP2_DIR}" \
    "${PHASE1_ANAT_STEP3_DIR}" \
    "${PHASE1_ANAT_STEP4_DIR}" \
    "${PHASE1_ANAT_STEP5_DIR}" \
    "${PHASE1_ANAT_STEP6_DIR}" \
    "${PHASE1_ANAT_STEP7_DIR}" \
    "${PHASE1_ANAT_VIS_DIR}" \
    "${PHASE1_ANAT_STEPVIEW_DIR}" \
    "${ATLAS_DIR}" \
    "${FMRI_ROOT_DIR}" \
    "${PHASE2_FMRI_VIS_DIR}" \
    "${PHASE2_FMRI_STEPVIEW_DIR}" \
    "${DWI_DIR}" \
    "${PHASE3_DWI_VIS_DIR}" \
    "${PHASE3_DWI_STEPVIEW_DIR}" \
    "${PHASE4_SUMMARY_DIR}" \
    "${FINAL_DIR}" \
    "${REPORTS_DIR}" \
    "${COMPARE_DIR}"

  ensure_visual_link "${PHASE0_INIT_DIR}/stepview" "${PHASE0_INIT_STEPVIEW_DIR}"
  ensure_visual_link "${PHASE1_ANAT_DIR}/stepview" "${PHASE1_ANAT_STEPVIEW_DIR}"
  ensure_visual_link "${PHASE1_ANAT_DIR}/visualization" "${PHASE1_ANAT_VIS_DIR}"
  ensure_visual_link "${PHASE2_FMRI_DIR}/stepview" "${PHASE2_FMRI_STEPVIEW_DIR}"
  ensure_visual_link "${PHASE2_FMRI_DIR}/visualization" "${PHASE2_FMRI_VIS_DIR}"
  ensure_visual_link "${PHASE3_DWI_DIR}/stepview" "${PHASE3_DWI_STEPVIEW_DIR}"
  ensure_visual_link "${PHASE3_DWI_DIR}/visualization" "${PHASE3_DWI_VIS_DIR}"
}

ensure_visual_link() {
  local legacy_path="$1"
  local target_path="$2"
  local item=""

  [[ -n "${legacy_path:-}" && -n "${target_path:-}" ]] || return 0
  mkdir -p "${target_path}"

  if [[ -L "${legacy_path}" ]]; then
    ln -sfn "${target_path}" "${legacy_path}"
    return 0
  fi

  if [[ -d "${legacy_path}" ]]; then
    if [[ "$(cd "${legacy_path}" && pwd -P)" != "$(cd "${target_path}" && pwd -P)" ]]; then
      (
        shopt -s dotglob nullglob
        for item in "${legacy_path}"/*; do
          [[ -e "${item}" ]] || continue
          if [[ ! -e "${target_path}/$(basename "${item}")" ]]; then
            mv "${item}" "${target_path}/"
          fi
        done
      )
      rmdir "${legacy_path}" 2>/dev/null || true
    fi
  fi

  if [[ ! -e "${legacy_path}" ]]; then
    ln -sfn "${target_path}" "${legacy_path}"
  fi
}

read_manifest_value() {
  local manifest_path="$1"
  local manifest_key="$2"
  [[ -f "$manifest_path" ]] || return 0
  awk -F '\t' -v target="$manifest_key" '$1 == target { print $2; exit }' "$manifest_path"
}

list_fmri_trial_names() {
  local trials_root="${INIT_STEP0_DIR}/trials"
  local manifest_path="${INIT_STEP0_DIR}/manifest.tsv"
  local func_source=""

  if [[ -d "$trials_root" ]]; then
    find "$trials_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
    return 0
  fi

  func_source="$(read_manifest_value "$manifest_path" "func_source")"
  if [[ -n "$func_source" ]]; then
    basename "$(dirname "$func_source")"
  fi
}

setup_fmri_trial_context() {
  local trial_name="${1:-}"
  local init_trial_dir=""

  if [[ -z "$trial_name" ]]; then
    trial_name="$(list_fmri_trial_names | head -n 1)"
  fi
  [[ -n "$trial_name" ]] || die "Failed to determine fMRI trial name"

  init_trial_dir="${INIT_STEP0_DIR}/trials/${trial_name}"
  if [[ ! -d "$init_trial_dir" ]]; then
    init_trial_dir="${INIT_STEP0_DIR}"
  fi

  FMRI_TRIAL_NAME="$trial_name"
  FMRI_TRIAL_INPUT_DIR="$init_trial_dir"
  FMRI_DIR="${FMRI_ROOT_DIR}/${FMRI_TRIAL_NAME}"
  PHASE2_FMRI_TRIAL_VIS_DIR="${PHASE2_FMRI_VIS_DIR}/${FMRI_TRIAL_NAME}"
  FMRI_STEPS_TRIAL_DIR="${PHASE2_FMRI_TRIAL_VIS_DIR}/stepview"
  FMRI_FUNC_INPUT="${FMRI_TRIAL_INPUT_DIR}/func.nii.gz"
  FMRI_FUNC_JSON="${FMRI_TRIAL_INPUT_DIR}/func.json"
  FMRI_FUNC_REF_INPUT="${FMRI_TRIAL_INPUT_DIR}/func_ref.nii.gz"
  FMRI_FUNC_REF_JSON="${FMRI_TRIAL_INPUT_DIR}/func_ref.json"

  mkdir -p "$FMRI_DIR" "$PHASE2_FMRI_TRIAL_VIS_DIR" "$FMRI_STEPS_TRIAL_DIR"
}

link_step_product_nifti() {
  local step_no="$1"
  local product_no="$2"
  local step_name="$3"
  local src_path="$4"
  local safe_name=""

  [[ -n "${FMRI_STEPS_TRIAL_DIR:-}" ]] || die "FMRI step directory not initialized"
  [[ -e "$src_path" ]] || return 0

  safe_name="${step_name// /_}"
  ln -sfn "$src_path" "${FMRI_STEPS_TRIAL_DIR}/step${step_no}-${product_no}_${safe_name}.nii.gz"
}

link_phase_product_nifti() {
  local stepview_dir="$1"
  local step_no="$2"
  local product_no="$3"
  local step_name="$4"
  local src_path="$5"
  local safe_name=""

  [[ -n "$stepview_dir" ]] || die "Phase stepview directory is empty"
  [[ -e "$src_path" ]] || return 0

  safe_name="${step_name// /_}"
  ln -sfn "$src_path" "${stepview_dir}/step${step_no}-${product_no}_${safe_name}.nii.gz"
}

link_step_nifti() {
  # 兼容旧调用方式，内部统一映射到新的 step{n}-{m}_*.nii.gz 命名。
  local step_no="$1"
  local step_name="$2"
  local src_path="$3"
  link_step_product_nifti "$step_no" 1 "$step_name" "$src_path"
}

setup_tools_env() {
  local conda_sh="/home/bryang/miniconda3/etc/profile.d/conda.sh"
  local conda_env="${MRI_ENV_HOME:-/data/bryang/project/CNS/tools/mri_env}"
  local fsl_home="${FSL_HOME:-/data/bryang/project/CNS/tools/fsl_official}"
  local fs_home="/data/bryang/project/CNS/tools/freesurfer/usr/local/freesurfer/8.0.0"
  local fs_license="/data/bryang/project/CNS/tools/freesurfer/license.txt"
  local fastsurfer_home="${FASTSURFER_HOME:-/data/bryang/project/CNS/tools/FastSurfer}"
  local fastsurfer_python="${FASTSURFER_PYTHON:-${fastsurfer_home}/.venv/bin/python}"
  local workbench_dir="${CARET7DIR:-/data/bryang/project/CNS/tools/connectome_workbench-v2.1.0/workbench/bin_linux64}"
  local tcsh_bin
  local shebang_stamp

  [[ -f "$conda_sh" ]] || die "Missing conda setup: $conda_sh"
  [[ -d "$conda_env" ]] || die "Missing MRI env: $conda_env"
  [[ -d "$fsl_home" ]] || die "Missing FSL: $fsl_home"
  [[ -f "$fsl_home/etc/fslconf/fsl.sh" ]] || die "Missing FSL config: $fsl_home/etc/fslconf/fsl.sh"
  [[ -d "$fs_home" ]] || die "Missing FreeSurfer: $fs_home"
  [[ -f "$fs_license" ]] || die "Missing FreeSurfer license: $fs_license"
  [[ -x "$workbench_dir/wb_command" ]] || die "Missing Workbench wb_command: $workbench_dir/wb_command"
  if [[ "${SURFER_TYPE:-free}" == "fast" ]]; then
    [[ -d "$fastsurfer_home" ]] || die "Missing FastSurfer: $fastsurfer_home"
    [[ -f "$fastsurfer_home/run_fastsurfer.sh" ]] || die "Missing FastSurfer entrypoint: $fastsurfer_home/run_fastsurfer.sh"
    [[ -x "$fastsurfer_python" ]] || die "Missing FastSurfer python: $fastsurfer_python"
  fi

  # shellcheck disable=SC1091
  source "$conda_sh"
  conda activate "$conda_env"
  tcsh_bin="${CONDA_PREFIX}/bin/tcsh"
  [[ -x "$tcsh_bin" ]] || die "Missing tcsh in MRI env: $tcsh_bin"

  export FSLDIR="$fsl_home"
  # shellcheck disable=SC1091
  source "$FSLDIR/etc/fslconf/fsl.sh"

  export ANTSPATH="$conda_env/bin"
  export FS_LICENSE="$fs_license"
  export FREESURFER_HOME="$fs_home"
  export FASTSURFER_HOME="$fastsurfer_home"
  export FASTSURFER_PYTHON="$fastsurfer_python"
  export CARET7DIR="$workbench_dir"
  export HCPPIPEDIR="${HCPPIPEDIR:-/data/bryang/project/CNS/tools/HCPpipelines-5.0.0}"

  # Some FreeSurfer helper scripts still hardcode /bin/csh or /bin/tcsh.
  # Rewrite those shebangs to the tcsh bundled in the active env.
  shebang_stamp="${FREESURFER_HOME}/.codex_tcsh_shebangs_${CONDA_PREFIX##*/}.stamp"
  if [[ ! -f "$shebang_stamp" ]]; then
    local fs_script first_line shebang_suffix tmp_script
    while IFS= read -r fs_script; do
      [[ -n "$fs_script" ]] || continue
      first_line="$(head -n 1 "$fs_script")"
      if [[ "$first_line" =~ ^\#![[:space:]]*/bin/(csh|tcsh)(.*)$ ]]; then
        shebang_suffix="${BASH_REMATCH[2]}"
        tmp_script="${fs_script}.tmp.$$"
        {
          printf '#!%s%s\n' "$tcsh_bin" "$shebang_suffix"
          tail -n +2 "$fs_script"
        } > "$tmp_script"
        chmod --reference="$fs_script" "$tmp_script"
        mv "$tmp_script" "$fs_script"
      fi
    done < <(grep -RIl '^\#![[:space:]]*/bin/csh\|^\#![[:space:]]*/bin/tcsh' "$FREESURFER_HOME")
    touch "$shebang_stamp"
  fi

  set +e
  set +u
  set +o pipefail
  # shellcheck disable=SC1091
  source "$FREESURFER_HOME/SetUpFreeSurfer.sh" >/dev/null
  local fs_status=$?
  set -euo pipefail
  (( fs_status == 0 )) || die "Failed to source FreeSurfer environment"

  # FSL 命令必须优先来自同一套完整安装，避免出现 epi_reg 来自 mri_env、
  # 但其内部再调用另一套 FSL 二进制的混搭状态。
  export PATH="$CARET7DIR:$FSLDIR/bin:$FSLDIR/share/fsl/bin:$ANTSPATH:$PATH"
  export PYTHON_BIN="${CONDA_PREFIX}/bin/python"
  export MRTRIX_NTHREADS="${NTHREADS}"
  export OMP_NUM_THREADS="${NTHREADS}"
  export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="${NTHREADS}"
  export MPLCONFIGDIR="${MPLCONFIGDIR:-/tmp/cns_matplotlib_${USER:-user}}"
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/cns_xdg_cache_${USER:-user}}"
  export MESA_SHADER_CACHE_DIR="${MESA_SHADER_CACHE_DIR:-${XDG_CACHE_HOME}/mesa_shader_cache}"
  export PYVISTA_OFF_SCREEN="${PYVISTA_OFF_SCREEN:-true}"
  mkdir -p "${MPLCONFIGDIR}"
  mkdir -p "${XDG_CACHE_HOME}" "${MESA_SHADER_CACHE_DIR}"

  # 这里要显式确认 FSL 主命令完整可用，避免 epi_reg 在运行中才暴露缺少 applywarp 的共性环境问题。
  require_cmd epi_reg
  require_cmd applywarp
  require_cmd flirt
  require_cmd fslmaths
}

write_minimal_json() {
  local out_json="$1"
  local kind="$2"
  local pe_dir="$3"
  case "$kind" in
    dwi)
      cat > "$out_json" <<EOF
{
  "PhaseEncodingDirection": "${pe_dir}",
  "TotalReadoutTime": ${DEFAULT_TOTAL_READOUT_TIME}
}
EOF
      ;;
    func)
      cat > "$out_json" <<EOF
{
  "RepetitionTime": ${DEFAULT_FUNC_TR},
  "PhaseEncodingDirection": "${pe_dir}",
  "TotalReadoutTime": ${DEFAULT_TOTAL_READOUT_TIME}
}
EOF
      ;;
    func_ref)
      cat > "$out_json" <<EOF
{
  "PhaseEncodingDirection": "${pe_dir}",
  "TotalReadoutTime": ${DEFAULT_TOTAL_READOUT_TIME}
}
EOF
      ;;
    t1)
      cat > "$out_json" <<'EOF'
{}
EOF
      ;;
    *)
      die "Unknown JSON kind: $kind"
      ;;
  esac
}

export SCRIPT_DIR PIPELINE_ROOT CONFIG_DIR UTILS_DIR
