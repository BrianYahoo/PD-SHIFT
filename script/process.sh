#!/usr/bin/env bash
set -euo pipefail

# 计算当前入口脚本所在目录，后面用它去调用五个 phase 入口脚本。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<'EOF'
Usage:
  bash process.sh --dataset <hcp|parkinson> [--surfer <free|fast>] [--subject <subject_key>]
EOF
}

DATASET_ARG=""
SURFER_ARG=""
SUBJECT_ARG=""

# 解析外部输入的 dataset 和可选 subject。
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dataset)
      [[ $# -ge 2 ]] || die "Missing value for --dataset"
      DATASET_ARG="$2"
      shift 2
      ;;
    --subject)
      [[ $# -ge 2 ]] || die "Missing value for --subject"
      SUBJECT_ARG="$2"
      shift 2
      ;;
    --surfer)
      [[ $# -ge 2 ]] || die "Missing value for --surfer"
      SURFER_ARG="$2"
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

[[ -n "$DATASET_ARG" ]] || die "Missing --dataset"
DATASET_ARG="$(normalize_dataset_type "$DATASET_ARG")"
SURFER_ARG="$(normalize_surfer_type "${SURFER_ARG:-free}")"
export PIPELINE_SURFER="$SURFER_ARG"
load_dataset_config "$DATASET_ARG"

if [[ -n "$SUBJECT_ARG" ]]; then
  mapfile -t SUBJECT_KEYS < <(printf '%s\n' "$(normalize_subject_key "$SUBJECT_ARG")")
else
  mapfile -t SUBJECT_KEYS < <(list_dataset_subject_keys "$DATASET_ARG")
fi

(( ${#SUBJECT_KEYS[@]} > 0 )) || die "No subjects found for ${DATASET_ARG}"

process_interrupted=0
handle_process_interrupt() {
  process_interrupted=1
}

# 按顺序处理当前 dataset 下的单个或全部 subject。
for subject_key in "${SUBJECT_KEYS[@]}"; do
  export PIPELINE_DATASET="$DATASET_ARG"
  export PIPELINE_SURFER="$SURFER_ARG"
  export PIPELINE_SUBJECT="$subject_key"
  unset PIPELINE_SUBJECT_DIR

  load_config
  trap handle_process_interrupt INT TERM HUP
  log "[process] ${DATASET_TYPE} ${SURFER_LABEL} ${SUBJECT_KEY}"

  bash "${SCRIPT_DIR}/phases/phase0_init.sh"
  (( process_interrupted == 0 )) || { log "[process] interrupted ${DATASET_TYPE} ${SURFER_LABEL} ${SUBJECT_KEY}"; exit 130; }
  bash "${SCRIPT_DIR}/phases/phase1_anat.sh"
  (( process_interrupted == 0 )) || { log "[process] interrupted ${DATASET_TYPE} ${SURFER_LABEL} ${SUBJECT_KEY}"; exit 130; }
  bash "${SCRIPT_DIR}/phases/phase2_fmri.sh"
  (( process_interrupted == 0 )) || { log "[process] interrupted ${DATASET_TYPE} ${SURFER_LABEL} ${SUBJECT_KEY}"; exit 130; }
  bash "${SCRIPT_DIR}/phases/phase3_dwi.sh"
  (( process_interrupted == 0 )) || { log "[process] interrupted ${DATASET_TYPE} ${SURFER_LABEL} ${SUBJECT_KEY}"; exit 130; }
  bash "${SCRIPT_DIR}/phases/phase4_summary.sh"
  (( process_interrupted == 0 )) || { log "[process] interrupted ${DATASET_TYPE} ${SURFER_LABEL} ${SUBJECT_KEY}"; exit 130; }
  trap - INT TERM HUP
done
