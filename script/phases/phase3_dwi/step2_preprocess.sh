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

# 检查当前 step 依赖的命令是否存在。
require_cmd "$PYTHON_BIN"
require_cmd dwidenoise
require_cmd mrdegibbs
require_cmd dwifslpreproc
require_cmd dwibiascorrect
require_cmd dwi2mask
require_cmd dwiextract
require_cmd mrmath
require_cmd mrcat
require_cmd mrconvert
require_cmd mrinfo

STEP2_DENOISE_LOG="${DWI_DIR}/step2_denoise_degibbs.log"
STEP2_EDDY_LOG="${DWI_DIR}/step2_dwifslpreproc.log"
STEP2_BIAS_LOG="${DWI_DIR}/step2_biascorrect_mask.log"
STEP2_EXPORT_LOG="${DWI_DIR}/step2_export.log"
STEP2_EDDY_GPU_LOCK_PATH=""
STEP2_EDDY_GPU_ASSIGNED=""
STEP2_EDDY_GPU_CUDA_VISIBLE_DEVICES_WAS_SET="0"
STEP2_EDDY_GPU_ORIG_CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-}"

eddy_step2_note() {
  local message="$1"
  log "[phase3_dwi] ${message}"
  printf '[%s] [phase3_dwi] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${message}" >>"${STEP2_EDDY_LOG}"
}

parse_eddy_cuda_devices() {
  local devices_csv="${1:-${DWI_EDDY_CUDA_DEVICES:-0,1,2,3,4,5,6,7}}"
  local -a raw_devices=()
  local device=""
  local clean_device=""
  IFS=',' read -r -a raw_devices <<<"${devices_csv}"
  for device in "${raw_devices[@]}"; do
    clean_device="${device//[[:space:]]/}"
    [[ -n "${clean_device}" ]] && printf '%s\n' "${clean_device}"
  done
}

eddy_cuda_candidate_devices() {
  local max_devices="${DWI_EDDY_CUDA_MAX_SELECTED_DEVICES:-5}"
  local -a configured_devices=()
  local -a selected_devices=()
  local -A configured_lookup=()
  local -a memory_rows=()
  local query_output=""
  local line=""
  local gpu_idx=""
  local mem_used=""
  local row=""

  mapfile -t configured_devices < <(parse_eddy_cuda_devices "${DWI_EDDY_CUDA_DEVICES:-0,1,2,3,4,5,6,7}")
  (( ${#configured_devices[@]} > 0 )) || die "DWI_EDDY_CUDA_DEVICES is empty"
  [[ "${max_devices}" =~ ^[0-9]+$ ]] && (( max_devices > 0 )) || max_devices="${#configured_devices[@]}"
  for gpu_idx in "${configured_devices[@]}"; do
    configured_lookup["${gpu_idx}"]=1
  done

  if [[ "${DWI_EDDY_CUDA_SELECTION:-least_memory}" == "least_memory" ]] && command -v nvidia-smi >/dev/null 2>&1; then
    query_output="$(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits 2>/dev/null || true)"
    if [[ -n "${query_output}" ]]; then
      while IFS= read -r line; do
        gpu_idx="${line%%,*}"
        mem_used="${line#*,}"
        gpu_idx="${gpu_idx//[[:space:]]/}"
        mem_used="${mem_used//[[:space:]]/}"
        if [[ -n "${configured_lookup[${gpu_idx}]:-}" && "${mem_used}" =~ ^[0-9]+$ ]]; then
          memory_rows+=("${mem_used}"$'\t'"${gpu_idx}")
        fi
      done <<<"${query_output}"
      if (( ${#memory_rows[@]} > 0 )); then
        printf '%s\n' "${memory_rows[@]}" | sort -n -k1,1 -k2,2n | head -n "${max_devices}" | while IFS=$'\t' read -r _ gpu_idx; do
          printf '%s\n' "${gpu_idx}"
        done
        return 0
      fi
    fi
  fi

  selected_devices=("${configured_devices[@]:0:max_devices}")
  printf '%s\n' "${selected_devices[@]}"
}

eddy_cuda_lock_is_stale() {
  local lock_path="$1"
  local owner_path="${lock_path}/owner.tsv"
  local owner_pid=""
  [[ -d "${lock_path}" ]] || return 1
  [[ -f "${owner_path}" ]] || return 0
  owner_pid="$(awk -F '\t' '$1=="pid" {print $2; exit}' "${owner_path}" 2>/dev/null || true)"
  [[ "${owner_pid}" =~ ^[0-9]+$ ]] || return 0
  if kill -0 "${owner_pid}" 2>/dev/null; then
    return 1
  fi
  return 0
}

release_eddy_cuda_lock() {
  if [[ -n "${STEP2_EDDY_GPU_LOCK_PATH}" && -d "${STEP2_EDDY_GPU_LOCK_PATH}" ]]; then
    eddy_step2_note "Step2 released eddy CUDA device ${STEP2_EDDY_GPU_ASSIGNED} for ${SUBJECT_ID}"
    rm -rf "${STEP2_EDDY_GPU_LOCK_PATH}"
  fi
  if [[ "${STEP2_EDDY_GPU_CUDA_VISIBLE_DEVICES_WAS_SET}" == "1" ]]; then
    export CUDA_VISIBLE_DEVICES="${STEP2_EDDY_GPU_ORIG_CUDA_VISIBLE_DEVICES}"
  else
    unset CUDA_VISIBLE_DEVICES || true
  fi
  STEP2_EDDY_GPU_LOCK_PATH=""
  STEP2_EDDY_GPU_ASSIGNED=""
}

acquire_eddy_cuda_lock() {
  local -a devices=()
  local device=""
  local lock_path=""
  local waited_sec=0
  local poll_sec="${DWI_EDDY_CUDA_LOCK_POLL_SEC:-15}"

  [[ "${DWI_EDDY_USE_CUDA:-0}" == "1" ]] || return 1
  [[ "${DWI_EDDY_CUDA_AUTO_ASSIGN:-0}" == "1" ]] || return 1
  command -v eddy_cuda >/dev/null 2>&1 || return 1
  command -v nvidia-smi >/dev/null 2>&1 || return 1
  nvidia-smi -L >/dev/null 2>&1 || return 1
  [[ "${poll_sec}" =~ ^[0-9]+$ ]] && (( poll_sec > 0 )) || poll_sec=15

  mkdir -p "${DWI_EDDY_CUDA_LOCK_DIR}"
  while true; do
    mapfile -t devices < <(eddy_cuda_candidate_devices)
    (( ${#devices[@]} > 0 )) || die "No usable eddy CUDA device candidates"
    for device in "${devices[@]}"; do
      lock_path="${DWI_EDDY_CUDA_LOCK_DIR}/gpu_${device}.lock"
      if [[ -d "${lock_path}" ]] && eddy_cuda_lock_is_stale "${lock_path}"; then
        rm -rf "${lock_path}"
      fi
      if mkdir "${lock_path}" 2>/dev/null; then
        printf 'pid\t%s\nsubject\t%s\ndataset\t%s\nsurfer\t%s\nacquired_at\t%s\n' \
          "$$" "${SUBJECT_ID}" "${DATASET_TYPE}" "${SURFER_TYPE}" "$(date '+%Y-%m-%d %H:%M:%S')" >"${lock_path}/owner.tsv"
        STEP2_EDDY_GPU_LOCK_PATH="${lock_path}"
        STEP2_EDDY_GPU_ASSIGNED="${device}"
        if [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]]; then
          STEP2_EDDY_GPU_CUDA_VISIBLE_DEVICES_WAS_SET="1"
          STEP2_EDDY_GPU_ORIG_CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES}"
        else
          STEP2_EDDY_GPU_CUDA_VISIBLE_DEVICES_WAS_SET="0"
          STEP2_EDDY_GPU_ORIG_CUDA_VISIBLE_DEVICES=""
        fi
        export CUDA_VISIBLE_DEVICES="${device}"
        eddy_step2_note "Step2 using eddy_cuda on GPU ${device} for ${SUBJECT_ID}; pool=$(eddy_cuda_candidate_devices | paste -sd, -)"
        return 0
      fi
    done
    if (( waited_sec == 0 || waited_sec % 60 == 0 )); then
      eddy_step2_note "Step2 waiting for free eddy CUDA device for ${SUBJECT_ID}; pool=$(printf '%s ' "${devices[@]}" | sed 's/[[:space:]]*$//')"
    fi
    sleep "${poll_sec}"
    waited_sec=$(( waited_sec + poll_sec ))
  done
}

trap 'release_eddy_cuda_lock' EXIT INT TERM HUP

# 如果 DWI 预处理主结果和导出结果已存在，则直接跳过。
if [[ -f "${DWI_DIR}/dwi_preproc_bias.mif" && -f "${DWI_DIR}/dwi_mask.mif" && -f "${DWI_DIR}/mean_b0.nii.gz" && -f "${DWI_DIR}/data.nii.gz" && -f "${DWI_DIR}/data.bvec" && -f "${DWI_DIR}/data.bval" && -f "${DWI_DIR}/brain_mask.nii.gz" ]]; then
  log "[phase3_dwi] Step2 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果去噪和 Gibbs 去伪影结果还不存在，则先完成这两步。
if [[ ! -f "${DWI_DIR}/dwi_den_gibbs.mif" ]]; then
  run_logged "${STEP2_DENOISE_LOG}" dwidenoise "${DWI_DIR}/dwi_raw.mif" "${DWI_DIR}/dwi_denoised.mif" -noise "${DWI_DIR}/noise.mif"
  run_logged "${STEP2_DENOISE_LOG}" mrdegibbs "${DWI_DIR}/dwi_denoised.mif" "${DWI_DIR}/dwi_den_gibbs.mif"
fi

# 如果预处理后的 DWI 还不存在，则执行 eddy/topup 流程。
if [[ ! -f "${DWI_DIR}/dwi_preproc.mif" ]]; then
  # 从 JSON 中读取相位编码方向。
  PE_DIR="$("$PYTHON_BIN" - "${INIT_STEP0_DIR}/dwi.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], "r", encoding="utf-8")).get("PhaseEncodingDirection", "i-"))
PY
)"
  # 统一定义传给 eddy 的参数。
  # 不显式传 --nthr，避免 GPU 版 eddy_cuda 因只接受 --nthr=1 而直接失败。
  # CPU 回退时改由 OpenMP 环境变量控制线程数。
  export OMP_NUM_THREADS="${NTHREADS}"
  EDDY_OPTS=" --slm=linear --repol --data_is_shelled "
  if [[ "${DWI_EDDY_USE_CUDA:-0}" == "1" ]]; then
    if acquire_eddy_cuda_lock; then
      :
    elif [[ "${DWI_EDDY_CUDA_AUTO_ASSIGN:-0}" == "1" ]]; then
      eddy_step2_note "Step2 could not auto-assign eddy CUDA device for ${SUBJECT_ID}; using eddy_cpu/default selection"
    elif [[ -n "${CUDA_VISIBLE_DEVICES:-}" ]] && command -v eddy_cuda >/dev/null 2>&1; then
      eddy_step2_note "Step2 using eddy_cuda with caller-provided CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES} for ${SUBJECT_ID}"
    else
      eddy_step2_note "Step2 CUDA requested for eddy on ${SUBJECT_ID}, but no explicit GPU assignment is active; using default FSL eddy selection"
    fi
  else
    eddy_step2_note "Step2 using eddy_cpu/default selection for ${SUBJECT_ID}"
  fi
  # 如果存在反向 DWI，则走成对反向相位编码预处理。
  if [[ -f "${DWI_DIR}/dwi_rev_raw.mif" ]]; then
    {
      printf '\n===== %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')"
      printf 'Command: dwiextract %q - -bzero | mrmath - mean %q -axis 3 -force\n' "${DWI_DIR}/dwi_den_gibbs.mif" "${DWI_DIR}/b0_main_mean.mif"
      dwiextract "${DWI_DIR}/dwi_den_gibbs.mif" - -bzero | mrmath - mean "${DWI_DIR}/b0_main_mean.mif" -axis 3 -force
      printf '\n===== %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')"
      printf 'Command: dwiextract %q - -bzero | mrmath - mean %q -axis 3 -force\n' "${DWI_DIR}/dwi_rev_raw.mif" "${DWI_DIR}/b0_rev_mean.mif"
      dwiextract "${DWI_DIR}/dwi_rev_raw.mif" - -bzero | mrmath - mean "${DWI_DIR}/b0_rev_mean.mif" -axis 3 -force
    } >>"${STEP2_EDDY_LOG}" 2>&1
    run_logged "${STEP2_EDDY_LOG}" mrcat "${DWI_DIR}/b0_main_mean.mif" "${DWI_DIR}/b0_rev_mean.mif" -axis 3 "${DWI_DIR}/se_epi_pair.mif" -force
    run_logged "${STEP2_EDDY_LOG}" dwifslpreproc "${DWI_DIR}/dwi_den_gibbs.mif" "${DWI_DIR}/dwi_preproc.mif" \
      -rpe_pair \
      -se_epi "${DWI_DIR}/se_epi_pair.mif" \
      -pe_dir "$PE_DIR" \
      -eddy_options "$EDDY_OPTS" \
      -scratch "${DWI_DIR}/scratch_dwifslpreproc" \
      -force
  # 如果不存在反向 DWI，则退回到无反向数据流程。
  else
    run_logged "${STEP2_EDDY_LOG}" dwifslpreproc "${DWI_DIR}/dwi_den_gibbs.mif" "${DWI_DIR}/dwi_preproc.mif" \
      -rpe_none \
      -pe_dir "$PE_DIR" \
      -eddy_options "$EDDY_OPTS" \
      -scratch "${DWI_DIR}/scratch_dwifslpreproc" \
      -force
  fi
  release_eddy_cuda_lock
fi

# 如果 bias 校正结果还不存在，则执行 bias 校正并生成脑掩膜。
if [[ ! -f "${DWI_DIR}/dwi_preproc_bias.mif" ]]; then
  run_logged "${STEP2_BIAS_LOG}" dwibiascorrect ants "${DWI_DIR}/dwi_preproc.mif" "${DWI_DIR}/dwi_preproc_bias.mif" -bias "${DWI_DIR}/dwi_bias.mif" -force
  run_logged "${STEP2_BIAS_LOG}" dwi2mask "${DWI_DIR}/dwi_preproc_bias.mif" "${DWI_DIR}/dwi_mask.mif" -force
fi

# 如果平均 b0 图像还不存在，则导出 mean b0 到 nifti。
if [[ ! -f "${DWI_DIR}/mean_b0.nii.gz" ]]; then
  {
    printf '\n===== %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'Command: dwiextract %q - -bzero | mrmath - mean %q -axis 3 -force\n' "${DWI_DIR}/dwi_preproc_bias.mif" "${DWI_DIR}/mean_b0.mif"
    dwiextract "${DWI_DIR}/dwi_preproc_bias.mif" - -bzero | mrmath - mean "${DWI_DIR}/mean_b0.mif" -axis 3 -force
  } >>"${STEP2_EXPORT_LOG}" 2>&1
  run_logged "${STEP2_EXPORT_LOG}" mrconvert "${DWI_DIR}/mean_b0.mif" "${DWI_DIR}/mean_b0.nii.gz" -force
fi

# 如果 FSL 兼容版 DWI 文件还不存在，则导出 data.nii.gz、bvec、bval 和脑掩膜。
if [[ ! -f "${DWI_DIR}/data.nii.gz" ]]; then
  run_logged "${STEP2_EXPORT_LOG}" mrconvert "${DWI_DIR}/dwi_preproc_bias.mif" "${DWI_DIR}/data.nii.gz" -force
  run_logged "${STEP2_EXPORT_LOG}" mrinfo "${DWI_DIR}/dwi_preproc_bias.mif" -export_grad_fsl "${DWI_DIR}/data.bvec" "${DWI_DIR}/data.bval"
  run_logged "${STEP2_EXPORT_LOG}" mrconvert "${DWI_DIR}/dwi_mask.mif" "${DWI_DIR}/brain_mask.nii.gz" -datatype uint8 -force
fi
