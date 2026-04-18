#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config

# 定义 TVP 建模输入矩阵的参考路径与当前导出目录。
TVP_ROOT="${SC_REFERENCE_ROOT}"
TVP_MODEL_DIR="${FINAL_DIR}/dwi/modeling/tvp"
STEP2_MANIFEST="${REPORTS_DIR}/step2_export_tvp_model_inputs_manifest.tsv"

TVP_CONN_EXCITATOR_IN="${TVP_ROOT}/conn_excitator.npy"
TVP_CONN_DOPAMINE_IN="${TVP_ROOT}/conn_dopamine.npy"
TVP_CONN_INHIBITOR_IN="${TVP_ROOT}/conn_inhibitor.npy"

TVP_CONN_EXCITATOR_OUT="${TVP_MODEL_DIR}/conn_excitator.npy"
TVP_CONN_DOPAMINE_OUT="${TVP_MODEL_DIR}/conn_dopamine.npy"
TVP_CONN_INHIBITOR_OUT="${TVP_MODEL_DIR}/conn_inhibitor.npy"

# 检查三张 TVP 建模矩阵是否存在。
[[ -f "${TVP_CONN_EXCITATOR_IN}" ]] || die "Missing TVP excitator matrix"
[[ -f "${TVP_CONN_DOPAMINE_IN}" ]] || die "Missing TVP dopamine matrix"
[[ -f "${TVP_CONN_INHIBITOR_IN}" ]] || die "Missing TVP inhibitor matrix"

# 如果建模输入包已经导出完成，则直接跳过。
if [[ -f "${TVP_CONN_EXCITATOR_OUT}" && -f "${TVP_CONN_DOPAMINE_OUT}" && -f "${TVP_CONN_INHIBITOR_OUT}" && -f "${STEP2_MANIFEST}" ]]; then
  log "[phase4_summary] Step2 already done for ${SUBJECT_ID}"
  exit 0
fi

# 创建 TVP 建模输入目录，并复制三张标准矩阵。
mkdir -p "${TVP_MODEL_DIR}"
cp -f "${TVP_CONN_EXCITATOR_IN}" "${TVP_CONN_EXCITATOR_OUT}"
cp -f "${TVP_CONN_DOPAMINE_IN}" "${TVP_CONN_DOPAMINE_OUT}"
cp -f "${TVP_CONN_INHIBITOR_IN}" "${TVP_CONN_INHIBITOR_OUT}"

# 写出本 step 的 manifest，记录参考来源与当前导出位置。
cat > "${STEP2_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
tvp_conn_excitator_input	${TVP_CONN_EXCITATOR_IN}
tvp_conn_dopamine_input	${TVP_CONN_DOPAMINE_IN}
tvp_conn_inhibitor_input	${TVP_CONN_INHIBITOR_IN}
tvp_conn_excitator_output	${TVP_CONN_EXCITATOR_OUT}
tvp_conn_dopamine_output	${TVP_CONN_DOPAMINE_OUT}
tvp_conn_inhibitor_output	${TVP_CONN_INHIBITOR_OUT}
EOF
