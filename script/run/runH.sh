#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"
LOG_DIR="${PIPELINE_ROOT}/logs/parallel/hcp/FastSurfer"
LOG_PATH="${LOG_DIR}/105923.log"

mkdir -p "${LOG_DIR}"

{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') start hcp FastSurfer 105923 ====="
  bash "${SCRIPT_ROOT}/process.sh" --dataset hcp --surfer fast --subject 105923
} 2>&1 | tee -a "${LOG_PATH}"

# HCP 全部 subject。
# bash "${SCRIPT_ROOT}/process.sh" --dataset hcp --surfer fast

# Parkinson 单个 subject。
# bash "${SCRIPT_ROOT}/process.sh" --dataset parkinson --surfer fast --subject example001

# Parkinson 全部 subject。
# bash "${SCRIPT_ROOT}/process.sh" --dataset parkinson --surfer fast
