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

# 检查当前 step 需要的输入工具是否已经可用。
require_cmd "$PYTHON_BIN"
if [[ "${INIT_T1_RESAMPLE_ENABLE:-0}" == "1" ]]; then
  require_cmd mri_convert
fi

# 定义 phase0_init step1 的输出清单文件。
PHASE0_STEP1_MANIFEST="${PHASE0_INIT_STEP1_DIR}/manifest.tsv"
TRIALS_ROOT="${PHASE0_INIT_STEP1_DIR}/trials"
TRIAL_MANIFEST="${PHASE0_INIT_STEP1_DIR}/func_trials.tsv"
PHASE0_STD_ROOT="${PHASE0_INIT_STEP1_DIR}/raw_standardized"

# 记录当前 step 选择了哪些原始输入，最后统一写入 manifest。
T1_SOURCE_RECORD=""
DWI_SOURCE_RECORD=""
DWI_REV_SOURCE_RECORD=""
PRIMARY_FUNC_SOURCE_RECORD=""
PRIMARY_FUNC_REF_SOURCE_RECORD=""
T1_ORIGINAL_ZOOMS_RECORD=""
T1_RESAMPLED_TO_1MM_RECORD="0"
T1_RESAMPLE_TARGET_MM_RECORD="${INIT_T1_RESAMPLE_VOXEL_SIZE:-1}"

image_zooms_csv() {
  local image_path="$1"
  "${PYTHON_BIN}" - "${image_path}" <<'PY'
import sys
import nibabel as nib
img = nib.load(sys.argv[1])
zooms = img.header.get_zooms()[:3]
print(",".join(f"{float(z):.6f}" for z in zooms))
PY
}

image_is_target_resolution() {
  local image_path="$1"
  local target_voxel_size="$2"
  "${PYTHON_BIN}" - "${image_path}" "${target_voxel_size}" <<'PY' >/dev/null 2>&1
import sys
import nibabel as nib
img = nib.load(sys.argv[1])
target = float(sys.argv[2])
zooms = [float(z) for z in img.header.get_zooms()[:3]]
ok = all(abs(z - target) < 1e-3 for z in zooms)
raise SystemExit(0 if ok else 1)
PY
}

image_requires_target_resample() {
  local image_path="$1"
  local target_voxel_size="$2"
  "${PYTHON_BIN}" - "${image_path}" "${target_voxel_size}" <<'PY' >/dev/null 2>&1
import sys
import nibabel as nib
img = nib.load(sys.argv[1])
target = float(sys.argv[2])
zooms = [float(z) for z in img.header.get_zooms()[:3]]
needs = any(abs(z - target) >= 1e-3 for z in zooms)
raise SystemExit(0 if needs else 1)
PY
}

resample_voxel_slug() {
  local voxel_size="$1"
  echo "${voxel_size//./p}"
}

phase0_step1_outputs_ready() {
  [[ -f "$PHASE0_STEP1_MANIFEST" \
    && -f "$TRIAL_MANIFEST" \
    && -f "${INIT_STEP0_DIR}/t1.nii.gz" \
    && -f "${INIT_STEP0_DIR}/t1.json" \
    && -f "${INIT_STEP0_DIR}/dwi.nii.gz" \
    && -f "${INIT_STEP0_DIR}/dwi.bval" \
    && -f "${INIT_STEP0_DIR}/dwi.bvec" \
    && -f "${INIT_STEP0_DIR}/dwi.json" \
    && -f "${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.nii.gz" \
    && -f "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.nii.gz" \
    && -f "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.json" \
    && -d "$TRIALS_ROOT" ]] || return 1

  find "${BIDS_SUBJECT_DIR}/func" -maxdepth 1 -type f -name "${SUBJECT_ID}_task-rest_run-*_dir-*_bold.nii.gz" | grep -q . || return 1

  if [[ "${INIT_T1_RESAMPLE_ENABLE:-0}" == "1" ]]; then
    local target_voxel_size="${INIT_T1_RESAMPLE_VOXEL_SIZE:-1}"
    local manifest_target_voxel_size=""
    local t1_resampled_flag=""
    manifest_target_voxel_size="$(awk -F '\t' '$1=="t1_resample_voxel_size_mm"{print $2}' "$PHASE0_STEP1_MANIFEST" 2>/dev/null || true)"
    t1_resampled_flag="$(awk -F '\t' '$1=="t1_resampled_to_1mm"{print $2}' "$PHASE0_STEP1_MANIFEST" 2>/dev/null || true)"
    if [[ -n "$manifest_target_voxel_size" && "$manifest_target_voxel_size" != "$target_voxel_size" ]]; then
      return 1
    fi
    if [[ "$t1_resampled_flag" == "1" ]]; then
      image_is_target_resolution "${INIT_STEP0_DIR}/t1.nii.gz" "$target_voxel_size" || return 1
      [[ -f "${INIT_STEP0_DIR}/t1_ori.nii.gz" ]] || return 1
    elif image_requires_target_resample "${INIT_STEP0_DIR}/t1.nii.gz" "$target_voxel_size"; then
      # 兼容旧 manifest：如果当前标准化后的 T1 仍然不是目标分辨率，说明还没走新的 init 重采样逻辑。
      return 1
    fi
  fi
}

write_trial_manifest_header() {
  # 先写 trial 清单表头，后面每个 trial 追加一行。
  cat > "$TRIAL_MANIFEST" <<EOF
trial_name	func_source	func_ref_source	bids_bold_nii	bids_bold_json
EOF
}

append_trial_manifest_row() {
  # 把当前 trial 的来源和 BIDS 输出位置记入清单。
  local trial_name="$1"
  local func_source="$2"
  local func_ref_source="$3"
  local bids_bold_nii="$4"
  local bids_bold_json="$5"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$trial_name" \
    "$func_source" \
    "$func_ref_source" \
    "$bids_bold_nii" \
    "$bids_bold_json" >> "$TRIAL_MANIFEST"
}

reset_phase0_step1_targets() {
  # 每次重新导入前先清理旧 trial、旧 BIDS func 和旧标准化中间文件，避免新旧结果混在一起。
  rm -rf "$TRIALS_ROOT" "$PHASE0_STD_ROOT"
  mkdir -p "$TRIALS_ROOT" "$PHASE0_STD_ROOT"
  rm -f \
    "${INIT_STEP0_DIR}/t1_ori.nii.gz" \
    "${INIT_STEP0_DIR}/func.nii.gz" \
    "${INIT_STEP0_DIR}/func.json" \
    "${INIT_STEP0_DIR}/func_ref.nii.gz" \
    "${INIT_STEP0_DIR}/func_ref.json" \
    "${INIT_STEP0_DIR}/dwi_rev.nii.gz" \
    "${INIT_STEP0_DIR}/dwi_rev.bval" \
    "${INIT_STEP0_DIR}/dwi_rev.bvec" \
    "${INIT_STEP0_DIR}/dwi_rev.json"
  rm -f "${BIDS_SUBJECT_DIR}/func/${SUBJECT_ID}_task-rest_run-"*_dir-*"_bold.nii.gz"
  rm -f "${BIDS_SUBJECT_DIR}/func/${SUBJECT_ID}_task-rest_run-"*_dir-*"_bold.json"
}

series_dir_label_from_source() {
  # 尽量从源目录名读出 LR/RL/AP/PA；如果读不出来，再退回到 PhaseEncodingDirection。
  local source_name="$1"
  local json_path="${2:-}"
  local base_name=""
  local pe_dir=""
  base_name="$(basename "$source_name")"

  if [[ "$base_name" == *"_LR"* ]]; then
    echo "LR"
    return 0
  fi
  if [[ "$base_name" == *"_RL"* ]]; then
    echo "RL"
    return 0
  fi
  if [[ "$base_name" == *"_PA"* ]]; then
    echo "PA"
    return 0
  fi
  if [[ "$base_name" == *"_AP"* ]]; then
    echo "AP"
    return 0
  fi

  if [[ -n "$json_path" && -f "$json_path" ]]; then
    pe_dir="$("$PYTHON_BIN" - "$json_path" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
mapping = {
    "i": "iPos",
    "i-": "iNeg",
    "j": "jPos",
    "j-": "jNeg",
    "k": "kPos",
    "k-": "kNeg",
}
print(mapping.get(str(data.get("PhaseEncodingDirection", "")).strip(), "UNK"))
PY
)"
    echo "$pe_dir"
    return 0
  fi

  echo "UNK"
}

run_dcm2niix_series() {
  # 对单个 DICOM 序列执行 dcm2niix，保留原始转换产物供追溯。
  local dicom_dir="$1"
  local out_dir="$2"
  mkdir -p "$out_dir"
  find "$out_dir" -mindepth 1 -maxdepth 1 -type f -delete
  dcm2niix -b y -z y -f %f_%p_%t_%s -o "$out_dir" "$dicom_dir" >"${out_dir}/dcm2niix.log" 2>&1
}

pick_converted_base() {
  # 从 dcm2niix 产物中挑选主 NIfTI，并返回不带扩展名的公共前缀。
  local out_dir="$1"
  local nii_path=""
  nii_path="$(pick_largest_matching_nifti "$out_dir" "*.nii.gz")"
  [[ -f "$nii_path" ]] || die "Failed to select converted NIfTI in ${out_dir}"
  echo "${nii_path%.nii.gz}"
}

stage_t1_nifti() {
  # Dataset-specific import code only selects the T1 source; this function owns
  # optional config-driven resolution staging and the shared BIDS copy.
  local source_nii="$1"
  local source_json="${2:-}"
  local target_voxel_size="${INIT_T1_RESAMPLE_VOXEL_SIZE:-1}"
  local target_slug=""
  local staged_target=""

  [[ -f "$source_nii" ]] || die "Missing T1 source NIfTI: ${source_nii}"
  mkdir -p "${PHASE0_STD_ROOT}/t1"

  target_slug="$(resample_voxel_slug "$target_voxel_size")"
  staged_target="${PHASE0_STD_ROOT}/t1/t1_resampled_${target_slug}mm.nii.gz"
  T1_ORIGINAL_ZOOMS_RECORD="$(image_zooms_csv "$source_nii")"
  T1_RESAMPLED_TO_1MM_RECORD="0"
  T1_RESAMPLE_TARGET_MM_RECORD="$target_voxel_size"
  if [[ "${INIT_T1_RESAMPLE_ENABLE:-0}" == "1" ]] && image_requires_target_resample "$source_nii" "$target_voxel_size"; then
    cp -f "$source_nii" "${INIT_STEP0_DIR}/t1_ori.nii.gz"
    mri_convert "${INIT_STEP0_DIR}/t1_ori.nii.gz" "$staged_target" -vs "$target_voxel_size" "$target_voxel_size" "$target_voxel_size" >"${PHASE0_STD_ROOT}/t1/mri_convert_t1_${target_slug}mm.log" 2>&1
    cp -f "$staged_target" "${INIT_STEP0_DIR}/t1.nii.gz"
    T1_RESAMPLED_TO_1MM_RECORD="1"
  else
    cp -f "$source_nii" "${INIT_STEP0_DIR}/t1.nii.gz"
  fi

  if [[ -n "$source_json" && -f "$source_json" ]]; then
    cp -f "$source_json" "${INIT_STEP0_DIR}/t1.json"
  else
    write_minimal_json "${INIT_STEP0_DIR}/t1.json" "t1" ""
  fi

  cp -f "${INIT_STEP0_DIR}/t1.nii.gz" "${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.nii.gz"
  cp -f "${INIT_STEP0_DIR}/t1.json" "${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.json"
}

parkinson_series_basename() {
  local series_path="$1"
  basename "$series_path"
}

parkinson_series_stem() {
  local series_name="$1"
  if [[ "$series_name" =~ ^(.+)_([0-9]{6})_([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  echo "$series_name"
}

parkinson_series_time_token() {
  local series_name="$1"
  if [[ "$series_name" =~ _([0-9]{6})_[0-9]+$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  echo "999999"
}

pick_earliest_parkinson_dir() {
  # 同一类重复序列默认选择更早时间的那一条；时间缺失时再按名字兜底。
  local selected_dir=""
  local selected_key=""
  local candidate_dir=""
  local candidate_name=""
  local candidate_key=""

  for candidate_dir in "$@"; do
    [[ -d "$candidate_dir" ]] || continue
    candidate_name="$(parkinson_series_basename "$candidate_dir")"
    candidate_key="$(parkinson_series_time_token "$candidate_name")|${candidate_name}"
    if [[ -z "$selected_dir" || "$candidate_key" < "$selected_key" ]]; then
      selected_dir="$candidate_dir"
      selected_key="$candidate_key"
    fi
  done

  echo "$selected_dir"
}

pick_parkinson_series_dir() {
  # 从当前受试者目录下按名字模式选择一个最合适的序列目录。
  local best_dir=""
  local -a candidate_dirs=()
  while (($# > 0)); do
    mapfile -d '' -t candidate_dirs < <(find "$SUBJECT_DIR" -mindepth 1 -maxdepth 1 -type d -iname "$1" -print0)
    best_dir="$(pick_earliest_parkinson_dir "${candidate_dirs[@]}")"
    if [[ -n "$best_dir" ]]; then
      echo "$best_dir"
      return 0
    fi
    shift
  done
  return 0
}

pick_opposite_dwi_dir() {
  # 如果存在 AP/PA 或 LR/RL 互补的 DWI 序列，则把它识别为反向相位编码输入。
  local main_dir="$1"
  local candidate=""
  local main_base=""
  main_base="$(basename "$main_dir")"

  if [[ "$main_base" == *"_PA_"* ]]; then
    candidate="${SUBJECT_DIR}/$(basename "${main_base/_PA_/_AP_}")"
  elif [[ "$main_base" == *"_AP_"* ]]; then
    candidate="${SUBJECT_DIR}/$(basename "${main_base/_AP_/_PA_}")"
  elif [[ "$main_base" == *"_LR_"* ]]; then
    candidate="${SUBJECT_DIR}/$(basename "${main_base/_LR_/_RL_}")"
  elif [[ "$main_base" == *"_RL_"* ]]; then
    candidate="${SUBJECT_DIR}/$(basename "${main_base/_RL_/_LR_}")"
  fi

  if [[ -n "$candidate" && -d "$candidate" && "$candidate" != "$main_dir" ]]; then
    echo "$candidate"
    return 0
  fi
}

pick_parkinson_ref_dir() {
  # 先按同名替换 SaveB->Ref 配对；如果不存在，再在同类 Ref 序列里选更早的一条。
  local func_dir="$1"
  local func_base=""
  local preferred=""
  local fallback=""
  local target_stem=""
  local candidate_dir=""
  local candidate_name=""
  local -a ref_candidates=()
  func_base="$(basename "$func_dir")"
  if [[ "$func_base" == *"Ref"* ]]; then
    return 0
  fi
  preferred="${SUBJECT_DIR}/$(basename "${func_dir/SaveB/Ref}")"
  if [[ -d "$preferred" ]]; then
    echo "$preferred"
    return 0
  fi

  target_stem="$(parkinson_series_stem "$(basename "${func_dir/SaveB/Ref}")")"
  mapfile -d '' -t ref_candidates < <(find "$SUBJECT_DIR" -mindepth 1 -maxdepth 1 -type d -iname 'restfMRI*Ref*' -print0)
  if (( ${#ref_candidates[@]} > 0 )); then
    for candidate_dir in "${ref_candidates[@]}"; do
      candidate_name="$(parkinson_series_basename "$candidate_dir")"
      if [[ "$(parkinson_series_stem "$candidate_name")" == "$target_stem" ]]; then
        fallback="${fallback:+$fallback"$'\n'"}${candidate_dir}"
      fi
    done
  fi

  if [[ -n "$fallback" ]]; then
    mapfile -t ref_candidates <<<"$fallback"
    pick_earliest_parkinson_dir "${ref_candidates[@]}"
    return 0
  fi

  fallback="$(pick_earliest_parkinson_dir "${ref_candidates[@]}")"
  echo "$fallback"
}

collect_parkinson_rest_main_dirs() {
  # rest 重复序列只保留更早的一条，并按实际采集时间排序。
  # 优先使用真正的主序列；如果某些受试者只有 Ref，则退回 Ref-only 导入。
  local candidate_dir=""
  local candidate_name=""
  local candidate_stem=""
  local candidate_key=""
  local stem=""
  local main_found="0"
  local -a ordered_stems=()
  local -a sorted_pairs=()
  local pair=""
  declare -A best_dir_by_stem=()
  declare -A best_key_by_stem=()

  while IFS= read -r -d '' candidate_dir; do
    main_found="1"
    candidate_name="$(parkinson_series_basename "$candidate_dir")"
    candidate_stem="$(parkinson_series_stem "$candidate_name")"
    candidate_key="$(parkinson_series_time_token "$candidate_name")|${candidate_name}"
    if [[ -z "${best_dir_by_stem[$candidate_stem]:-}" ]]; then
      ordered_stems+=("$candidate_stem")
      best_dir_by_stem["$candidate_stem"]="$candidate_dir"
      best_key_by_stem["$candidate_stem"]="$candidate_key"
      continue
    fi
    if [[ "$candidate_key" < "${best_key_by_stem[$candidate_stem]}" ]]; then
      best_dir_by_stem["$candidate_stem"]="$candidate_dir"
      best_key_by_stem["$candidate_stem"]="$candidate_key"
    fi
  done < <(find "$SUBJECT_DIR" -mindepth 1 -maxdepth 1 -type d \( -iname 'restfMRI*SaveB*' -o -iname 'restfMRI*' \) ! -iname '*Ref*' -print0)

  if [[ "$main_found" == "0" ]]; then
    while IFS= read -r -d '' candidate_dir; do
      candidate_name="$(parkinson_series_basename "$candidate_dir")"
      candidate_stem="$(parkinson_series_stem "$candidate_name")"
      candidate_key="$(parkinson_series_time_token "$candidate_name")|${candidate_name}"
      if [[ -z "${best_dir_by_stem[$candidate_stem]:-}" ]]; then
        ordered_stems+=("$candidate_stem")
        best_dir_by_stem["$candidate_stem"]="$candidate_dir"
        best_key_by_stem["$candidate_stem"]="$candidate_key"
        continue
      fi
      if [[ "$candidate_key" < "${best_key_by_stem[$candidate_stem]}" ]]; then
        best_dir_by_stem["$candidate_stem"]="$candidate_dir"
        best_key_by_stem["$candidate_stem"]="$candidate_key"
      fi
    done < <(find "$SUBJECT_DIR" -mindepth 1 -maxdepth 1 -type d -iname 'restfMRI*Ref*' -print0)
  fi

  for stem in "${ordered_stems[@]}"; do
    [[ -n "${best_dir_by_stem[$stem]:-}" ]] || continue
    sorted_pairs+=("${best_key_by_stem[$stem]}|${best_dir_by_stem[$stem]}")
  done

  if (( ${#sorted_pairs[@]} == 0 )); then
    return 0
  fi

  while IFS= read -r pair; do
    [[ -n "$pair" ]] || continue
    echo "${pair##*|}"
  done < <(printf '%s\n' "${sorted_pairs[@]}" | sort)
}

import_hcp_phase0_step1() {
  # HCP 原始目录本身已经是 NIfTI，因此这里只做标准化导入和 BIDS 化。
  local hcp_root=""
  local t1_dir=""
  local dwi_dir_raw=""
  local dwi_base=""
  local dwi_dir_token=""
  local dwi_pe_token=""
  local dwi_src=""
  local dwi_rev_src=""
  local t1_src=""
  local primary_func_src=""
  local primary_func_ref_src=""
  local bids_run=""
  local bids_dir=""
  local bids_base=""
  local rest_dir=""
  local trial_name=""
  local trial_dir=""
  local trial_func_src=""
  local trial_func_ref_src=""
  local trial_func_base=""
  local trial_json=""

  hcp_root="${SUBJECT_DIR}/unprocessed/3T"
  [[ -d "$hcp_root" ]] || die "Missing HCP 3T input: $hcp_root"

  t1_dir="$(pick_first_existing_dir "${hcp_root}/T1w_MPR1" "${hcp_root}/T1w_MPR2")"
  dwi_dir_raw="${hcp_root}/Diffusion"
  mapfile -t REST_DIRS < <(find "$hcp_root" -mindepth 1 -maxdepth 1 -type d -name 'rfMRI_REST*' | sort)

  [[ -d "$t1_dir" ]] || die "Missing HCP T1 input dir"
  [[ -d "$dwi_dir_raw" ]] || die "Missing HCP DWI input dir"
  (( ${#REST_DIRS[@]} > 0 )) || die "Missing HCP rfMRI input dir"

  t1_src="$(pick_largest_matching_nifti "$t1_dir" "*T1w*.nii.gz" "*_SBRef*.nii.gz")"
  dwi_src="$(pick_largest_matching_nifti "$dwi_dir_raw" "*DWI_dir*_LR.nii.gz" "*_SBRef*.nii.gz")"
  if [[ -z "$dwi_src" ]]; then
    dwi_src="$(pick_largest_matching_nifti "$dwi_dir_raw" "*DWI_dir*.nii.gz" "*_SBRef*.nii.gz")"
  fi

  [[ -f "$t1_src" ]] || die "Failed to select HCP T1 NIfTI"
  [[ -f "$dwi_src" ]] || die "Failed to select HCP DWI NIfTI"

  dwi_rev_src=""
  dwi_base="$(basename "$dwi_src")"
  if [[ "$dwi_base" =~ (DWI_dir[0-9]+)_([A-Z]{2}) ]]; then
    dwi_dir_token="${BASH_REMATCH[1]}"
    dwi_pe_token="${BASH_REMATCH[2]}"
    if [[ "$dwi_pe_token" == "LR" ]]; then
      dwi_rev_src="$(pick_largest_matching_nifti "$dwi_dir_raw" "*${dwi_dir_token}_RL.nii.gz" "*_SBRef*.nii.gz")"
    elif [[ "$dwi_pe_token" == "RL" ]]; then
      dwi_rev_src="$(pick_largest_matching_nifti "$dwi_dir_raw" "*${dwi_dir_token}_LR.nii.gz" "*_SBRef*.nii.gz")"
    fi
  fi

  stage_t1_nifti "$t1_src" ""

  cp -f "$dwi_src" "${INIT_STEP0_DIR}/dwi.nii.gz"
  cp -f "${dwi_src%.nii.gz}.bval" "${INIT_STEP0_DIR}/dwi.bval"
  cp -f "${dwi_src%.nii.gz}.bvec" "${INIT_STEP0_DIR}/dwi.bvec"
  write_minimal_json "${INIT_STEP0_DIR}/dwi.json" "dwi" "$(infer_pe_from_name "$dwi_src" "i-")"
  cp -f "${INIT_STEP0_DIR}/dwi.nii.gz" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.nii.gz"
  cp -f "${INIT_STEP0_DIR}/dwi.bval" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.bval"
  cp -f "${INIT_STEP0_DIR}/dwi.bvec" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.bvec"
  cp -f "${INIT_STEP0_DIR}/dwi.json" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.json"

  if [[ -n "$dwi_rev_src" && -f "$dwi_rev_src" ]]; then
    cp -f "$dwi_rev_src" "${INIT_STEP0_DIR}/dwi_rev.nii.gz"
    cp -f "${dwi_rev_src%.nii.gz}.bval" "${INIT_STEP0_DIR}/dwi_rev.bval"
    cp -f "${dwi_rev_src%.nii.gz}.bvec" "${INIT_STEP0_DIR}/dwi_rev.bvec"
    write_minimal_json "${INIT_STEP0_DIR}/dwi_rev.json" "dwi" "$(infer_pe_from_name "$dwi_rev_src" "i")"
  fi

  primary_func_src=""
  primary_func_ref_src=""
  for rest_dir in "${REST_DIRS[@]}"; do
    trial_name="$(basename "$rest_dir")"
    trial_dir="${TRIALS_ROOT}/${trial_name}"
    trial_func_src="$(pick_largest_matching_nifti "$rest_dir" "*rfMRI_REST*.nii.gz" "*_SBRef*.nii.gz")"
    trial_func_ref_src=""

    [[ -f "$trial_func_src" ]] || die "Failed to select HCP fMRI NIfTI for ${trial_name}"
    mkdir -p "$trial_dir"

    trial_func_base="$(basename "$trial_func_src")"
    if [[ "$trial_func_base" == *"_LR"* ]]; then
      trial_func_ref_src="$(pick_largest_matching_nifti "$rest_dir" "*SpinEchoFieldMap_RL.nii.gz")"
    elif [[ "$trial_func_base" == *"_RL"* ]]; then
      trial_func_ref_src="$(pick_largest_matching_nifti "$rest_dir" "*SpinEchoFieldMap_LR.nii.gz")"
    fi
    if [[ -z "$trial_func_ref_src" ]]; then
      trial_func_ref_src="$(pick_largest_matching_nifti "$rest_dir" "*SpinEchoFieldMap*.nii.gz")"
    fi

    cp -f "$trial_func_src" "${trial_dir}/func.nii.gz"
    write_minimal_json "${trial_dir}/func.json" "func" "$(infer_pe_from_name "$trial_func_src" "i-")"
    if [[ -n "$trial_func_ref_src" && -f "$trial_func_ref_src" ]]; then
      cp -f "$trial_func_ref_src" "${trial_dir}/func_ref.nii.gz"
      write_minimal_json "${trial_dir}/func_ref.json" "func_ref" "$(infer_pe_from_name "$trial_func_ref_src" "i")"
    fi

    if [[ -z "$primary_func_src" ]]; then
      primary_func_src="$trial_func_src"
      primary_func_ref_src="$trial_func_ref_src"
      cp -f "${trial_dir}/func.nii.gz" "${INIT_STEP0_DIR}/func.nii.gz"
      cp -f "${trial_dir}/func.json" "${INIT_STEP0_DIR}/func.json"
      if [[ -f "${trial_dir}/func_ref.nii.gz" ]]; then
        cp -f "${trial_dir}/func_ref.nii.gz" "${INIT_STEP0_DIR}/func_ref.nii.gz"
        cp -f "${trial_dir}/func_ref.json" "${INIT_STEP0_DIR}/func_ref.json"
      fi
    fi

    bids_run="1"
    if [[ "$trial_name" =~ REST([0-9]+)_([A-Z]{2})$ ]]; then
      bids_run="${BASH_REMATCH[1]}"
    fi
    trial_json="${trial_dir}/func.json"
    bids_dir="$(series_dir_label_from_source "$trial_name" "$trial_json")"
    bids_base="${BIDS_SUBJECT_DIR}/func/${SUBJECT_ID}_task-rest_run-${bids_run}_dir-${bids_dir}_bold"
    cp -f "${trial_dir}/func.nii.gz" "${bids_base}.nii.gz"
    cp -f "${trial_dir}/func.json" "${bids_base}.json"
    append_trial_manifest_row "$trial_name" "$trial_func_src" "$trial_func_ref_src" "${bids_base}.nii.gz" "${bids_base}.json"
  done

  T1_SOURCE_RECORD="$t1_src"
  DWI_SOURCE_RECORD="$dwi_src"
  DWI_REV_SOURCE_RECORD="$dwi_rev_src"
  PRIMARY_FUNC_SOURCE_RECORD="$primary_func_src"
  PRIMARY_FUNC_REF_SOURCE_RECORD="$primary_func_ref_src"
}

import_parkinson_phase0_step1() {
  # Parkinson 原始目录是 DICOM，必须先用 dcm2niix 做无损标准化转换。
  local t1_dicom_dir=""
  local dwi_dicom_dir=""
  local dwi_rev_dicom_dir=""
  local t1_base=""
  local dwi_base=""
  local dwi_rev_base=""
  local func_dicom_dir=""
  local func_ref_dicom_dir=""
  local func_base=""
  local func_ref_base=""
  local trial_name=""
  local trial_dir=""
  local run_idx=0
  local bids_dir=""
  local bids_base=""
  local func_json=""

  require_cmd dcm2niix

  t1_dicom_dir="$(pick_parkinson_series_dir 't1_*' 'T1_*' 'mprage*')"
  dwi_dicom_dir="$(pick_parkinson_series_dir 'dMRI*' 'dwi*')"
  mapfile -t REST_MAIN_DIRS < <(collect_parkinson_rest_main_dirs)

  [[ -d "$t1_dicom_dir" ]] || die "Missing Parkinson T1 DICOM dir"
  [[ -d "$dwi_dicom_dir" ]] || die "Missing Parkinson DWI DICOM dir"
  (( ${#REST_MAIN_DIRS[@]} > 0 )) || die "Missing Parkinson rest fMRI DICOM dir"

  run_dcm2niix_series "$t1_dicom_dir" "${PHASE0_STD_ROOT}/t1"
  t1_base="$(pick_converted_base "${PHASE0_STD_ROOT}/t1")"
  stage_t1_nifti "${t1_base}.nii.gz" "${t1_base}.json"

  run_dcm2niix_series "$dwi_dicom_dir" "${PHASE0_STD_ROOT}/dwi"
  dwi_base="$(pick_converted_base "${PHASE0_STD_ROOT}/dwi")"
  cp -f "${dwi_base}.nii.gz" "${INIT_STEP0_DIR}/dwi.nii.gz"
  cp -f "${dwi_base}.json" "${INIT_STEP0_DIR}/dwi.json"
  cp -f "${dwi_base}.bval" "${INIT_STEP0_DIR}/dwi.bval"
  cp -f "${dwi_base}.bvec" "${INIT_STEP0_DIR}/dwi.bvec"
  cp -f "${INIT_STEP0_DIR}/dwi.nii.gz" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.nii.gz"
  cp -f "${INIT_STEP0_DIR}/dwi.json" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.json"
  cp -f "${INIT_STEP0_DIR}/dwi.bval" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.bval"
  cp -f "${INIT_STEP0_DIR}/dwi.bvec" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.bvec"

  dwi_rev_dicom_dir="$(pick_opposite_dwi_dir "$dwi_dicom_dir")"
  if [[ -n "$dwi_rev_dicom_dir" && -d "$dwi_rev_dicom_dir" ]]; then
    run_dcm2niix_series "$dwi_rev_dicom_dir" "${PHASE0_STD_ROOT}/dwi_rev"
    dwi_rev_base="$(pick_converted_base "${PHASE0_STD_ROOT}/dwi_rev")"
    cp -f "${dwi_rev_base}.nii.gz" "${INIT_STEP0_DIR}/dwi_rev.nii.gz"
    cp -f "${dwi_rev_base}.json" "${INIT_STEP0_DIR}/dwi_rev.json"
    cp -f "${dwi_rev_base}.bval" "${INIT_STEP0_DIR}/dwi_rev.bval"
    cp -f "${dwi_rev_base}.bvec" "${INIT_STEP0_DIR}/dwi_rev.bvec"
  fi

  for func_dicom_dir in "${REST_MAIN_DIRS[@]}"; do
    run_idx=$((run_idx + 1))
    trial_name="$(basename "$func_dicom_dir")"
    trial_dir="${TRIALS_ROOT}/${trial_name}"
    mkdir -p "$trial_dir"

    run_dcm2niix_series "$func_dicom_dir" "${PHASE0_STD_ROOT}/func/${trial_name}"
    func_base="$(pick_converted_base "${PHASE0_STD_ROOT}/func/${trial_name}")"
    cp -f "${func_base}.nii.gz" "${trial_dir}/func.nii.gz"
    cp -f "${func_base}.json" "${trial_dir}/func.json"

    func_ref_dicom_dir="$(pick_parkinson_ref_dir "$func_dicom_dir")"
    if [[ -n "$func_ref_dicom_dir" && -d "$func_ref_dicom_dir" ]]; then
      run_dcm2niix_series "$func_ref_dicom_dir" "${PHASE0_STD_ROOT}/func_ref/${trial_name}"
      func_ref_base="$(pick_converted_base "${PHASE0_STD_ROOT}/func_ref/${trial_name}")"
      cp -f "${func_ref_base}.nii.gz" "${trial_dir}/func_ref.nii.gz"
      cp -f "${func_ref_base}.json" "${trial_dir}/func_ref.json"
    fi

    if [[ -z "$PRIMARY_FUNC_SOURCE_RECORD" ]]; then
      PRIMARY_FUNC_SOURCE_RECORD="$func_dicom_dir"
      PRIMARY_FUNC_REF_SOURCE_RECORD="$func_ref_dicom_dir"
      cp -f "${trial_dir}/func.nii.gz" "${INIT_STEP0_DIR}/func.nii.gz"
      cp -f "${trial_dir}/func.json" "${INIT_STEP0_DIR}/func.json"
      if [[ -f "${trial_dir}/func_ref.nii.gz" ]]; then
        cp -f "${trial_dir}/func_ref.nii.gz" "${INIT_STEP0_DIR}/func_ref.nii.gz"
        cp -f "${trial_dir}/func_ref.json" "${INIT_STEP0_DIR}/func_ref.json"
      fi
    fi

    func_json="${trial_dir}/func.json"
    bids_dir="$(series_dir_label_from_source "$trial_name" "$func_json")"
    bids_base="${BIDS_SUBJECT_DIR}/func/${SUBJECT_ID}_task-rest_run-${run_idx}_dir-${bids_dir}_bold"
    cp -f "${trial_dir}/func.nii.gz" "${bids_base}.nii.gz"
    cp -f "${trial_dir}/func.json" "${bids_base}.json"
    append_trial_manifest_row "$trial_name" "$func_dicom_dir" "$func_ref_dicom_dir" "${bids_base}.nii.gz" "${bids_base}.json"
  done

  T1_SOURCE_RECORD="$t1_dicom_dir"
  DWI_SOURCE_RECORD="$dwi_dicom_dir"
  DWI_REV_SOURCE_RECORD="$dwi_rev_dicom_dir"
}

# 输出当前 step 的开始日志。
log "[phase0_init] Step1 bids standardize for ${SUBJECT_ID}"

# 如果 phase0_init step1 的标准输入和 BIDS 多 trial 文件都已齐全，则直接跳过。
if phase0_step1_outputs_ready; then
  log "[phase0_init] Step1 already done for ${SUBJECT_ID}"
  exit 0
fi

reset_phase0_step1_targets
write_trial_manifest_header

# 按 dataset config 选择原始数据导入逻辑，避免在流程代码里写 dataset 判断。
case "${DATASET_IMPORT_MODE}" in
  hcp_nifti)
    import_hcp_phase0_step1
    ;;
  parkinson_dicom)
    import_parkinson_phase0_step1
    ;;
  *)
    die "Unsupported DATASET_IMPORT_MODE in phase0_init step1: ${DATASET_IMPORT_MODE}"
    ;;
esac

# 记录 phase0_init step1 选用了哪些源文件以及 BIDS 输出位置。
cat > "$PHASE0_STEP1_MANIFEST" <<EOF
key	value
subject_id	${SUBJECT_ID}
dataset_type	${DATASET_TYPE}
raw_standardization_root	${PHASE0_STD_ROOT}
t1_source	${T1_SOURCE_RECORD}
t1_original_zooms_mm	${T1_ORIGINAL_ZOOMS_RECORD}
t1_resampled	${T1_RESAMPLED_TO_1MM_RECORD}
t1_resampled_to_1mm	${T1_RESAMPLED_TO_1MM_RECORD}
t1_resample_enable	${INIT_T1_RESAMPLE_ENABLE:-0}
t1_resample_config	${INIT_T1_RESAMPLE_ENABLE:-0}
t1_resample_voxel_size_mm	${T1_RESAMPLE_TARGET_MM_RECORD}
dwi_source	${DWI_SOURCE_RECORD}
dwi_rev_source	${DWI_REV_SOURCE_RECORD}
func_source	${PRIMARY_FUNC_SOURCE_RECORD}
func_ref_source	${PRIMARY_FUNC_REF_SOURCE_RECORD}
func_trials_tsv	${TRIAL_MANIFEST}
bids_subject_dir	${BIDS_SUBJECT_DIR}
EOF

# 把 phase0_init 的关键输入结果链接到 stepview，便于快速检查。
link_phase_product_nifti "${PHASE0_INIT_STEPVIEW_DIR}" 1 1 "t1_bids_input" "${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.nii.gz"
if [[ -f "${INIT_STEP0_DIR}/t1_ori.nii.gz" ]]; then
  link_phase_product_nifti "${PHASE0_INIT_STEPVIEW_DIR}" 1 5 "t1_ori" "${INIT_STEP0_DIR}/t1_ori.nii.gz"
fi
link_phase_product_nifti "${PHASE0_INIT_STEPVIEW_DIR}" 1 2 "dwi_bids_input" "${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.nii.gz"
if [[ -f "${PHASE0_INIT_STEP1_DIR}/dwi_rev.nii.gz" ]]; then
  link_phase_product_nifti "${PHASE0_INIT_STEPVIEW_DIR}" 1 3 "dwi_reverse_input" "${PHASE0_INIT_STEP1_DIR}/dwi_rev.nii.gz"
fi
if [[ -f "${PHASE0_INIT_STEP1_DIR}/func.nii.gz" ]]; then
  link_phase_product_nifti "${PHASE0_INIT_STEPVIEW_DIR}" 1 4 "fmri_primary_input" "${PHASE0_INIT_STEP1_DIR}/func.nii.gz"
fi
