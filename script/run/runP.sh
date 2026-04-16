#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PIPELINE_ROOT="$(cd "${SCRIPT_ROOT}/.." && pwd)"
LOG_DIR="${PIPELINE_ROOT}/logs/parallel/parkinson/FastSurfer"
LOG_PATH="${LOG_DIR}/001.log"

mkdir -p "${LOG_DIR}"

{
  echo "===== $(date '+%Y-%m-%d %H:%M:%S') start parkinson FastSurfer 001 ====="
  bash "${SCRIPT_ROOT}/process.sh" --dataset parkinson --surfer fast --subject 001
} 2>&1 | tee -a "${LOG_PATH}"

# HCP 单个 subject。
# bash "${SCRIPT_ROOT}/process.sh" --dataset hcp --surfer fast --subject 105923

# HCP 全部 subject。
# bash "${SCRIPT_ROOT}/process.sh" --dataset hcp --surfer fast

# Parkinson 全部 subject。
# bash "${SCRIPT_ROOT}/process.sh" --dataset parkinson --surfer fast
