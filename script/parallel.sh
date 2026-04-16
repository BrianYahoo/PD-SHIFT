#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash parallel.sh --dataset <hcp|parkinson> --surfer <free|fast> [--subject <subject_key> ...]
EOF
}

LOG_ROOT="${PIPELINE_PARALLEL_LOG_ROOT:-${PIPELINE_ROOT}/logs/parallel}"
MAX_PARALLEL="${MAX_PARALLEL:-5}"
FAIL_COUNT=0
DATASET_ARG=""
SURFER_ARG=""
declare -a SUBJECT_ARGS=()
declare -a ACTIVE_PIDS=()
declare -A PID_TO_DATASET=()
declare -A PID_TO_SURFER_LABEL=()
declare -A PID_TO_SUBJECT=()
declare -A PID_TO_STATUS_FILE=()
TOTAL_SUBJECT_COUNT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dataset)
      [[ $# -ge 2 ]] || die "Missing value for --dataset"
      DATASET_ARG="$2"
      shift 2
      ;;
    --surfer)
      [[ $# -ge 2 ]] || die "Missing value for --surfer"
      SURFER_ARG="$2"
      shift 2
      ;;
    --subject)
      [[ $# -ge 2 ]] || die "Missing value for --subject"
      SUBJECT_ARGS+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      die "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${DATASET_ARG}" ]] || die "Missing --dataset"
[[ -n "${SURFER_ARG}" ]] || die "Missing --surfer"
DATASET_ARG="$(normalize_dataset_type "${DATASET_ARG}")"
SURFER_ARG="$(normalize_surfer_type "${SURFER_ARG}")"
SURFER_LABEL="$(surfer_label "${SURFER_ARG}")"
export PIPELINE_DATASET="${DATASET_ARG}"
export PIPELINE_SURFER="${SURFER_ARG}"
load_dataset_config "${DATASET_ARG}"

parse_cuda_devices() {
  local devices_csv="${1:-${FASTSURFER_CUDA_DEVICES:-0,1,2,3,4,5,6,7}}"
  local -a raw_devices=()
  local device=""
  local clean_device=""
  IFS=',' read -r -a raw_devices <<<"${devices_csv}"
  for device in "${raw_devices[@]}"; do
    clean_device="${device//[[:space:]]/}"
    [[ -n "$clean_device" ]] && printf '%s\n' "$clean_device"
  done
}

cuda_candidate_devices() {
  local max_devices="${FASTSURFER_CUDA_MAX_SELECTED_DEVICES:-5}"
  local -a configured_devices=()
  local -a selected_devices=()
  local query_output=""
  local line=""
  local gpu_idx=""
  local mem_used=""
  local configured=""
  local -a memory_sorted_devices=()
  mapfile -t configured_devices < <(parse_cuda_devices "${FASTSURFER_CUDA_DEVICES:-0,1,2,3,4,5,6,7}")
  (( ${#configured_devices[@]} > 0 )) || die "FASTSURFER_CUDA_DEVICES is empty"
  [[ "$max_devices" =~ ^[0-9]+$ ]] && (( max_devices > 0 )) || max_devices="${#configured_devices[@]}"

  if [[ "${FASTSURFER_CUDA_SELECTION:-round_robin}" == "least_memory" ]] && command -v nvidia-smi >/dev/null 2>&1; then
    query_output="$(nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits 2>/dev/null || true)"
    if [[ -n "$query_output" ]]; then
      mapfile -t memory_sorted_devices < <(
        while IFS= read -r line; do
          gpu_idx="${line%%,*}"
          mem_used="${line#*,}"
          gpu_idx="${gpu_idx//[[:space:]]/}"
          mem_used="${mem_used//[[:space:]]/}"
          for configured in "${configured_devices[@]}"; do
            if [[ "$gpu_idx" == "$configured" && "$mem_used" =~ ^[0-9]+$ ]]; then
              printf '%s\t%s\n' "$mem_used" "$gpu_idx"
            fi
          done
        done <<<"$query_output" | sort -n -k1,1 -k2,2n | head -n "$max_devices" | awk -F '\t' '{print $2}'
      )
      if (( ${#memory_sorted_devices[@]} > 0 )); then
        printf '%s\n' "${memory_sorted_devices[@]}"
        return 0
      fi
    fi
  fi

  selected_devices=("${configured_devices[@]:0:max_devices}")
  printf '%s\n' "${selected_devices[@]}"
}

cuda_device_for_launch_index() {
  local launch_index="$1"
  local -a devices=()
  mapfile -t devices < <(cuda_candidate_devices)
  (( ${#devices[@]} > 0 )) || die "No usable FastSurfer CUDA device candidates"
  echo "${devices[$(( launch_index % ${#devices[@]} ))]}"
}

setup_fastsurfer_cuda_for_subject() {
  local surfer="$1"
  local subject="$2"
  local launch_index="$3"
  local cuda_device=""

  [[ "$surfer" == "fast" ]] || return 0
  [[ "${FASTSURFER_USE_CUDA:-0}" == "1" ]] || return 0

  if [[ "${FASTSURFER_CUDA_AUTO_ASSIGN:-0}" == "1" ]] && { [[ -z "${CUDA_VISIBLE_DEVICES:-}" ]] || (( TOTAL_SUBJECT_COUNT > 1 )); }; then
    cuda_device="$(cuda_device_for_launch_index "$launch_index")"
    export CUDA_VISIBLE_DEVICES="$cuda_device"
  fi

  [[ -f "${FASTSURFER_CUDA_ENV_SCRIPT}" ]] || die "Missing FastSurfer CUDA env script: ${FASTSURFER_CUDA_ENV_SCRIPT}"
  # shellcheck disable=SC1090
  source "${FASTSURFER_CUDA_ENV_SCRIPT}"
  export FASTSURFER_DEVICE="cuda"
  export FASTSURFER_VIEWAGG_DEVICE="cuda"
  echo "[parallel] FastSurfer CUDA enabled for ${subject}: CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-unset}, selection=${FASTSURFER_CUDA_SELECTION:-round_robin}, pool=$(cuda_candidate_devices | paste -sd, -), FASTSURFER_PYTHON=${FASTSURFER_PYTHON}"
}

run_one_subject() {
  local dataset="$1"
  local surfer="$2"
  local surfer_label="$3"
  local subject="$4"
  local launch_index="$5"
  local subject_log_dir="${LOG_ROOT}/${dataset}/${surfer_label}"
  local subject_log="${subject_log_dir}/${subject}.log"
  local subject_status="${subject_log}.status"
  log "[parallel] start ${dataset} ${surfer_label} ${subject}"
  mkdir -p "${subject_log_dir}"
  : > "${subject_log}"
  rm -f "${subject_status}"
  (
    finalize_subject_run() {
      local exit_code=$?
      if (( exit_code == 0 )); then
        printf '[%s] success %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${dataset}" "${surfer_label}" "${subject}" >>"${subject_log}"
        printf 'success\n' >"${subject_status}"
      else
        printf '[%s] failed %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${dataset}" "${surfer_label}" "${subject}" >>"${subject_log}"
        printf 'failed\n' >"${subject_status}"
      fi
    }

    trap finalize_subject_run EXIT
    trap 'exit 130' INT TERM HUP

    {
      echo "===== $(date '+%Y-%m-%d %H:%M:%S') start ${dataset} ${surfer_label} ${subject} ====="
      setup_fastsurfer_cuda_for_subject "${surfer}" "${subject}" "${launch_index}"
      bash "${SCRIPT_DIR}/process.sh" --dataset "${dataset}" --surfer "${surfer}" --subject "${subject}"
    } >>"${subject_log}" 2>&1
  ) &
  ACTIVE_PIDS+=("$!")
  PID_TO_DATASET["$!"]="${dataset}"
  PID_TO_SURFER_LABEL["$!"]="${surfer_label}"
  PID_TO_SUBJECT["$!"]="${subject}"
  PID_TO_STATUS_FILE["$!"]="${subject_status}"
}

remove_active_pid() {
  local target_pid="$1"
  local kept=()
  local pid=""
  for pid in "${ACTIVE_PIDS[@]}"; do
    [[ "${pid}" == "${target_pid}" ]] || kept+=("${pid}")
  done
  ACTIVE_PIDS=("${kept[@]}")
}

harvest_subject_result() {
  local finished_pid="$1"
  local dataset="${PID_TO_DATASET[$finished_pid]:-}"
  local surfer_label="${PID_TO_SURFER_LABEL[$finished_pid]:-}"
  local subject="${PID_TO_SUBJECT[$finished_pid]:-}"
  local status_file="${PID_TO_STATUS_FILE[$finished_pid]:-}"
  local run_state="failed"

  [[ -n "${dataset}" ]] || return 0
  if [[ -f "${status_file}" ]]; then
    run_state="$(tr -d '[:space:]' <"${status_file}")"
    rm -f "${status_file}"
  fi

  if [[ "${run_state}" == "success" ]]; then
    log "[parallel] done ${dataset} ${surfer_label} ${subject}"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    log "[parallel] failed ${dataset} ${surfer_label} ${subject}"
  fi

  remove_active_pid "${finished_pid}"
  unset PID_TO_DATASET["$finished_pid"] PID_TO_SURFER_LABEL["$finished_pid"] PID_TO_SUBJECT["$finished_pid"] PID_TO_STATUS_FILE["$finished_pid"]
}

find_finished_subject_pid() {
  local pid=""
  for pid in "${ACTIVE_PIDS[@]}"; do
    if [[ -f "${PID_TO_STATUS_FILE[$pid]:-}" ]]; then
      echo "${pid}"
      return 0
    fi
  done
  for pid in "${ACTIVE_PIDS[@]}"; do
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "${pid}"
      return 0
    fi
  done
  sleep 0.1
  for pid in "${ACTIVE_PIDS[@]}"; do
    if [[ -f "${PID_TO_STATUS_FILE[$pid]:-}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
      echo "${pid}"
      return 0
    fi
  done
  return 1
}

wait_one_subject() {
  local finished_pid=""
  set +e
  wait -n
  set -e
  finished_pid="$(find_finished_subject_pid || true)"
  [[ -n "${finished_pid}" ]] && harvest_subject_result "${finished_pid}"
}

cleanup_parallel_jobs() {
  local pid=""
  trap - INT TERM HUP
  for pid in "${ACTIVE_PIDS[@]}"; do
    kill "${pid}" 2>/dev/null || true
  done
  for pid in "${ACTIVE_PIDS[@]}"; do
    set +e
    wait "${pid}" >/dev/null 2>&1
    set -e
    harvest_subject_result "${pid}"
  done
  exit 130
}

run_many_subjects() {
  local dataset="$1"
  local surfer="$2"
  local surfer_label="$3"
  shift 3
  local subjects=("$@")
  local running_jobs=0
  local launch_index=0
  local subject=""

  trap cleanup_parallel_jobs INT TERM HUP

  for subject in "${subjects[@]}"; do
    run_one_subject "${dataset}" "${surfer}" "${surfer_label}" "${subject}" "${launch_index}"
    launch_index=$((launch_index + 1))
    running_jobs=$((running_jobs + 1))

    if (( running_jobs >= MAX_PARALLEL )); then
      wait_one_subject
      running_jobs=$((running_jobs - 1))
    fi
  done

  while (( running_jobs > 0 )); do
    wait_one_subject
    running_jobs=$((running_jobs - 1))
  done

  if (( FAIL_COUNT > 0 )); then
    die "parallel finished with ${FAIL_COUNT} failed subject(s)"
  fi
}

if (( ${#SUBJECT_ARGS[@]} > 0 )); then
  mapfile -t ALL_SUBJECTS < <(printf '%s\n' "${SUBJECT_ARGS[@]}" | while IFS= read -r s; do normalize_subject_key "$s"; done)
else
  mapfile -t ALL_SUBJECTS < <(list_dataset_subject_keys "${DATASET_ARG}")
fi

(( ${#ALL_SUBJECTS[@]} > 0 )) || die "No subjects found for ${DATASET_ARG}"
TOTAL_SUBJECT_COUNT="${#ALL_SUBJECTS[@]}"
run_many_subjects "${DATASET_ARG}" "${SURFER_ARG}" "${SURFER_LABEL}" "${ALL_SUBJECTS[@]}"
