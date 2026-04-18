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
require_cmd tck2connectome
require_cmd "$PYTHON_BIN"

matrix_matches_current_atlas() {
  local matrix_path="$1"
  [[ -f "${matrix_path}" ]] || return 1
  "${PYTHON_BIN}" - "${matrix_path}" "${DWI_DIR}/atlas_in_dwi.nii.gz" <<'PY'
import sys
import nibabel as nib
import numpy as np

matrix = np.loadtxt(sys.argv[1], delimiter=",")
atlas = np.asarray(nib.load(sys.argv[2]).dataobj)
atlas_max = int(np.max(atlas))
ok = matrix.ndim == 2 and matrix.shape[0] == matrix.shape[1] == atlas_max
raise SystemExit(0 if ok else 1)
PY
}

run_connectome() {
  local out_csv="$1"
  local radial_search="$2"
  local weight_mode="$3"
  local scale_mode="$4"
  local -a args=()

  if [[ "${weight_mode}" == "sift2" ]]; then
    args+=(-tck_weights_in "${DWI_DIR}/sift2_weights.txt")
  fi
  if [[ "${scale_mode}" == "invnodevol" ]]; then
    args+=(-scale_invnodevol)
  fi

  tck2connectome "${DWI_DIR}/tracks.tck" "${DWI_DIR}/atlas_in_dwi.nii.gz" "${out_csv}" \
    "${args[@]}" \
    -symmetric -zero_diagonal -assignment_radial_search "${radial_search}" -nthreads "${NTHREADS}"
}

# 主流程默认使用配置里的 radial search，同时额外生成 radial=4 的对比实验结果。
# 每个 radial 都保留 count/sift2 与 raw/invnodevol 两个维度，因此总共是四类矩阵。
MAIN_RADIAL_SEARCH="${CONNECTOME_ASSIGNMENT_RADIAL_SEARCH:-2}"
COMPARE_RADIAL_SEARCH=4

# 主流程四类矩阵。
MAIN_SC_SIFT2="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv"
MAIN_SC_SIFT2_INVNODEVOL="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv"
MAIN_SC_COUNT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv"
MAIN_SC_COUNT_INVNODEVOL="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv"

# radial4 对照四类矩阵。
COMPARE_SC_SIFT2="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv"
COMPARE_SC_SIFT2_INVNODEVOL="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv"
COMPARE_SC_COUNT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv"
COMPARE_SC_COUNT_INVNODEVOL="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv"

VIS_DIR="${PHASE3_DWI_VIS_DIR}"
COMPARE_RADIAL_PNG="${VIS_DIR}/compare_radial.png"
COMPARE_RADIAL_INVNODEVOL_PNG="${VIS_DIR}/compare_radial_invnodevol.png"
MAIN_SC_SIFT2_REPAIR_REPORT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_zero_label_repair.json"
MAIN_SC_SIFT2_INVNODEVOL_REPAIR_REPORT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_zero_label_repair.json"
MAIN_SC_COUNT_REPAIR_REPORT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_zero_label_repair.json"
MAIN_SC_COUNT_INVNODEVOL_REPAIR_REPORT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_zero_label_repair.json"

mkdir -p "$VIS_DIR"

reset_matrix_if_shape_mismatch() {
  local matrix_path="$1"
  shift
  if [[ -f "${matrix_path}" ]] && ! matrix_matches_current_atlas "${matrix_path}"; then
    rm -f "${matrix_path}" "$@"
  fi
}

reset_matrix_if_shape_mismatch "$MAIN_SC_SIFT2" "$MAIN_SC_SIFT2_REPAIR_REPORT"
reset_matrix_if_shape_mismatch "$MAIN_SC_SIFT2_INVNODEVOL" "$MAIN_SC_SIFT2_INVNODEVOL_REPAIR_REPORT"
reset_matrix_if_shape_mismatch "$MAIN_SC_COUNT" "$MAIN_SC_COUNT_REPAIR_REPORT"
reset_matrix_if_shape_mismatch "$MAIN_SC_COUNT_INVNODEVOL" "$MAIN_SC_COUNT_INVNODEVOL_REPAIR_REPORT"
reset_matrix_if_shape_mismatch "$COMPARE_SC_SIFT2"
reset_matrix_if_shape_mismatch "$COMPARE_SC_SIFT2_INVNODEVOL"
reset_matrix_if_shape_mismatch "$COMPARE_SC_COUNT"
reset_matrix_if_shape_mismatch "$COMPARE_SC_COUNT_INVNODEVOL"

repair_zero_label_connectome_if_needed() {
  local matrix_path="$1"
  local repair_report="$2"
  local weight_mode="$3"
  local scale_mode="$4"

  if [[ "${DWI_CONNECTOME_REPAIR_ZERO_PROTECTED_LABELS:-1}" != "1" ]]; then
    return 0
  fi

  "${PYTHON_BIN}" "${UTILS_DIR}/phase3_dwi/step6/repair_zero_connection_labels.py" \
    --tracks "${DWI_DIR}/tracks.tck" \
    --atlas "${DWI_DIR}/atlas_in_dwi.nii.gz" \
    --matrix "${matrix_path}" \
    --output "${matrix_path}.fixed" \
    --report "${repair_report}" \
    --weight-mode "${weight_mode}" \
    --scale-mode "${scale_mode}" \
    --sift2-weights "${DWI_DIR}/sift2_weights.txt" \
    --radial-search "${MAIN_RADIAL_SEARCH}" \
    --protected-labels "${DWI_SMALL_NUCLEI_PROTECTED_LABELS:-41,42,43,44,45,46,87,88}" \
    --max-dilation "${DWI_CONNECTOME_ZERO_LABEL_MAX_DILATION:-12}" \
    --nthreads "${NTHREADS}"
  mv -f "${matrix_path}.fixed" "${matrix_path}"
}

# 如果主流程、对比实验和可视化都已存在，则直接跳过。
if [[ -f "$MAIN_SC_SIFT2" \
   && -f "$MAIN_SC_SIFT2_INVNODEVOL" \
   && -f "$MAIN_SC_COUNT" \
   && -f "$MAIN_SC_COUNT_INVNODEVOL" \
   && -f "$COMPARE_SC_SIFT2" \
   && -f "$COMPARE_SC_SIFT2_INVNODEVOL" \
   && -f "$COMPARE_SC_COUNT" \
   && -f "$COMPARE_SC_COUNT_INVNODEVOL" \
   && -f "$COMPARE_RADIAL_PNG" \
   && -f "$COMPARE_RADIAL_INVNODEVOL_PNG" \
   && -f "${DWI_DIR}/manifest.tsv" ]] \
  && { [[ "${DWI_CONNECTOME_REPAIR_ZERO_PROTECTED_LABELS:-1}" != "1" ]] || { [[ -f "${MAIN_SC_SIFT2_REPAIR_REPORT}" ]] && [[ -f "${MAIN_SC_SIFT2_INVNODEVOL_REPAIR_REPORT}" ]] && [[ -f "${MAIN_SC_COUNT_REPAIR_REPORT}" ]] && [[ -f "${MAIN_SC_COUNT_INVNODEVOL_REPAIR_REPORT}" ]]; }; }; then
  log "[phase3_dwi] Step6 already done for ${SUBJECT_ID}"
  exit 0
fi

# 主流程：未缩放的 SIFT2 矩阵。
if [[ ! -f "$MAIN_SC_SIFT2" ]]; then
  run_connectome "$MAIN_SC_SIFT2" "$MAIN_RADIAL_SEARCH" "sift2" "raw"
fi
repair_zero_label_connectome_if_needed "$MAIN_SC_SIFT2" "$MAIN_SC_SIFT2_REPAIR_REPORT" "sift2" "raw"

# 主流程：按 node volume 归一化的 SIFT2 矩阵。
if [[ ! -f "$MAIN_SC_SIFT2_INVNODEVOL" ]]; then
  run_connectome "$MAIN_SC_SIFT2_INVNODEVOL" "$MAIN_RADIAL_SEARCH" "sift2" "invnodevol"
fi
repair_zero_label_connectome_if_needed "$MAIN_SC_SIFT2_INVNODEVOL" "$MAIN_SC_SIFT2_INVNODEVOL_REPAIR_REPORT" "sift2" "invnodevol"

# 主流程：未缩放的 streamline count 矩阵。
if [[ ! -f "$MAIN_SC_COUNT" ]]; then
  run_connectome "$MAIN_SC_COUNT" "$MAIN_RADIAL_SEARCH" "count" "raw"
fi
repair_zero_label_connectome_if_needed "$MAIN_SC_COUNT" "$MAIN_SC_COUNT_REPAIR_REPORT" "count" "raw"

# 主流程：按 node volume 归一化的 streamline count 矩阵。
if [[ ! -f "$MAIN_SC_COUNT_INVNODEVOL" ]]; then
  run_connectome "$MAIN_SC_COUNT_INVNODEVOL" "$MAIN_RADIAL_SEARCH" "count" "invnodevol"
fi
repair_zero_label_connectome_if_needed "$MAIN_SC_COUNT_INVNODEVOL" "$MAIN_SC_COUNT_INVNODEVOL_REPAIR_REPORT" "count" "invnodevol"

# radial4：未缩放的 SIFT2 矩阵。
if [[ ! -f "$COMPARE_SC_SIFT2" ]]; then
  run_connectome "$COMPARE_SC_SIFT2" "$COMPARE_RADIAL_SEARCH" "sift2" "raw"
fi

# radial4：按 node volume 归一化的 SIFT2 矩阵。
if [[ ! -f "$COMPARE_SC_SIFT2_INVNODEVOL" ]]; then
  run_connectome "$COMPARE_SC_SIFT2_INVNODEVOL" "$COMPARE_RADIAL_SEARCH" "sift2" "invnodevol"
fi

# radial4：未缩放的 count 矩阵。
if [[ ! -f "$COMPARE_SC_COUNT" ]]; then
  run_connectome "$COMPARE_SC_COUNT" "$COMPARE_RADIAL_SEARCH" "count" "raw"
fi

# radial4：按 node volume 归一化的 count 矩阵。
if [[ ! -f "$COMPARE_SC_COUNT_INVNODEVOL" ]]; then
  run_connectome "$COMPARE_SC_COUNT_INVNODEVOL" "$COMPARE_RADIAL_SEARCH" "count" "invnodevol"
fi

# 输出未缩放版本的 radial 2 vs radial 4 对比图。
if [[ ! -f "$COMPARE_RADIAL_PNG" ]]; then
  "$PYTHON_BIN" "${UTILS_DIR}/phase3_dwi/step6/compare_connectome_radial.py" \
    --matrix-main "$MAIN_SC_SIFT2" \
    --matrix-compare "$COMPARE_SC_SIFT2" \
    --main-label "radial=${MAIN_RADIAL_SEARCH} sift2" \
    --compare-label "radial=${COMPARE_RADIAL_SEARCH} sift2" \
    --output "$COMPARE_RADIAL_PNG"
fi

# 输出 invnodevol 版本的 radial 2 vs radial 4 对比图。
if [[ ! -f "$COMPARE_RADIAL_INVNODEVOL_PNG" ]]; then
  "$PYTHON_BIN" "${UTILS_DIR}/phase3_dwi/step6/compare_connectome_radial.py" \
    --matrix-main "$MAIN_SC_SIFT2_INVNODEVOL" \
    --matrix-compare "$COMPARE_SC_SIFT2_INVNODEVOL" \
    --main-label "radial=${MAIN_RADIAL_SEARCH} sift2 invnodevol" \
    --compare-label "radial=${COMPARE_RADIAL_SEARCH} sift2 invnodevol" \
    --output "$COMPARE_RADIAL_INVNODEVOL_PNG"
fi

# 写出 DWI 分支的最终输出清单。
cat > "${DWI_DIR}/manifest.tsv" <<EOF
key	value
subject_id	${SUBJECT_ID}
dwi_input	${INIT_STEP0_DIR}/dwi.nii.gz
dwi_preproc	${DWI_DIR}/dwi_preproc_bias.mif
atlas_in_dwi	${DWI_DIR}/atlas_in_dwi.nii.gz
tracks	${DWI_DIR}/tracks.tck
sift2_weights	${DWI_DIR}/sift2_weights.txt
sc_sift2	${MAIN_SC_SIFT2}
sc_sift2_invnodevol	${MAIN_SC_SIFT2_INVNODEVOL}
sc_count	${MAIN_SC_COUNT}
sc_count_invnodevol	${MAIN_SC_COUNT_INVNODEVOL}
sc_sift2_zero_label_repair_report	${MAIN_SC_SIFT2_REPAIR_REPORT}
sc_sift2_invnodevol_zero_label_repair_report	${MAIN_SC_SIFT2_INVNODEVOL_REPAIR_REPORT}
sc_count_zero_label_repair_report	${MAIN_SC_COUNT_REPAIR_REPORT}
sc_count_invnodevol_zero_label_repair_report	${MAIN_SC_COUNT_INVNODEVOL_REPAIR_REPORT}
sc_sift2_radial4	${COMPARE_SC_SIFT2}
sc_sift2_invnodevol_radial4	${COMPARE_SC_SIFT2_INVNODEVOL}
sc_count_radial4	${COMPARE_SC_COUNT}
sc_count_invnodevol_radial4	${COMPARE_SC_COUNT_INVNODEVOL}
compare_radial_png	${COMPARE_RADIAL_PNG}
compare_radial_invnodevol_png	${COMPARE_RADIAL_INVNODEVOL_PNG}
sc_variants	sift2,sift2_invnodevol,count,count_invnodevol
assignment_radial_search_main	${MAIN_RADIAL_SEARCH}
assignment_radial_search_compare	${COMPARE_RADIAL_SEARCH}
EOF
