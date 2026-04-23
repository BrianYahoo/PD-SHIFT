#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash auto_fastsurfer_cuda.sh --slot <index> -- <command> [args...]

Environment:
  FASTSURFER_CUDA_DEVICES      Comma-separated GPU ids. Default: 0,1,2,3,4,5,6,7
  FASTSURFER_CUDA_SELECTION    round_robin|least_memory. Default: least_memory
  FASTSURFER_CUDA_MAX_SELECTED_DEVICES  Number of least-used GPUs to use. Default: 5
  FASTSURFER_CUDA_ENV_SCRIPT   CUDA env script. Default: /data/bryang/project/tools/use_fastsurfer_cuda_env.sh
EOF
}

SLOT_INDEX=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slot)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      SLOT_INDEX="$2"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$SLOT_INDEX" ]] || { usage >&2; exit 2; }
[[ $# -gt 0 ]] || { usage >&2; exit 2; }

DEVICES_CSV="${FASTSURFER_CUDA_DEVICES:-0,1,2,3,4,5,6,7}"
CUDA_SELECTION="${FASTSURFER_CUDA_SELECTION:-least_memory}"
MAX_SELECTED="${FASTSURFER_CUDA_MAX_SELECTED_DEVICES:-5}"
CUDA_ENV_SCRIPT="${FASTSURFER_CUDA_ENV_SCRIPT:-/data/bryang/project/tools/use_fastsurfer_cuda_env.sh}"

IFS=',' read -r -a RAW_DEVICES <<<"${DEVICES_CSV}"
DEVICES=()
for device in "${RAW_DEVICES[@]}"; do
  device="${device//[[:space:]]/}"
  [[ -n "$device" ]] && DEVICES+=("$device")
done

(( ${#DEVICES[@]} > 0 )) || { echo "[ERROR] FASTSURFER_CUDA_DEVICES is empty" >&2; exit 1; }
[[ -f "$CUDA_ENV_SCRIPT" ]] || { echo "[ERROR] Missing FastSurfer CUDA env script: $CUDA_ENV_SCRIPT" >&2; exit 1; }
[[ "$MAX_SELECTED" =~ ^[0-9]+$ ]] && (( MAX_SELECTED > 0 )) || MAX_SELECTED="${#DEVICES[@]}"

SELECTED_DEVICES=()
if [[ "$CUDA_SELECTION" == "least_memory" ]] && command -v nvidia-smi >/dev/null 2>&1; then
  while IFS= read -r selected; do
    [[ -n "$selected" ]] && SELECTED_DEVICES+=("$selected")
  done < <(
    nvidia-smi --query-gpu=index,memory.used --format=csv,noheader,nounits 2>/dev/null \
      | while IFS= read -r line; do
          gpu_idx="${line%%,*}"
          mem_used="${line#*,}"
          gpu_idx="${gpu_idx//[[:space:]]/}"
          mem_used="${mem_used//[[:space:]]/}"
          for configured in "${DEVICES[@]}"; do
            if [[ "$gpu_idx" == "$configured" && "$mem_used" =~ ^[0-9]+$ ]]; then
              printf '%s\t%s\n' "$mem_used" "$gpu_idx"
            fi
          done
        done \
      | sort -n -k1,1 -k2,2n \
      | head -n "$MAX_SELECTED" \
      | awk -F '\t' '{print $2}'
  )
fi

if (( ${#SELECTED_DEVICES[@]} == 0 )); then
  SELECTED_DEVICES=("${DEVICES[@]:0:MAX_SELECTED}")
fi

export CUDA_VISIBLE_DEVICES="${SELECTED_DEVICES[$(( SLOT_INDEX % ${#SELECTED_DEVICES[@]} ))]}"
# shellcheck disable=SC1090
source "$CUDA_ENV_SCRIPT"

exec "$@"
