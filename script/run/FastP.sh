#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

bash "${SCRIPT_ROOT}/parallel.sh" --surfer fast --dataset parkinson "$@"
