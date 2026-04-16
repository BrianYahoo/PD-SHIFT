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

# 根据配置决定是否启用体积归一化参数 -scale_invnodevol。
CONNECTOME_SCALE_ARGS=()
if [[ "${CONNECTOME_SCALE_INVNODEVOL:-1}" == "1" ]]; then
  CONNECTOME_SCALE_ARGS+=("-scale_invnodevol")
fi

# 主流程默认使用配置里的 2 mm，同时额外生成 4 mm 对比实验结果。
MAIN_RADIAL_SEARCH="${CONNECTOME_ASSIGNMENT_RADIAL_SEARCH:-2}"
COMPARE_RADIAL_SEARCH=4
MAIN_SC_SIFT2="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv"
MAIN_SC_COUNT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv"
COMPARE_SC_SIFT2="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv"
COMPARE_SC_COUNT="${DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv"
VIS_DIR="${DWI_DIR}/visualization"
COMPARE_RADIAL_PNG="${VIS_DIR}/compare_radial.png"

mkdir -p "$VIS_DIR"

# 如果主流程、对比实验和可视化都已存在，则直接跳过。
if [[ -f "$MAIN_SC_SIFT2" && -f "$MAIN_SC_COUNT" && -f "$COMPARE_SC_SIFT2" && -f "$COMPARE_SC_COUNT" && -f "$COMPARE_RADIAL_PNG" && -f "${DWI_DIR}/manifest.tsv" ]]; then
  log "[phase3_dwi] Step6 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果加权 SC 矩阵还不存在，则使用 SIFT2 权重生成加权 connectome。
if [[ ! -f "$MAIN_SC_SIFT2" ]]; then
  tck2connectome "${DWI_DIR}/tracks.tck" "${DWI_DIR}/atlas_in_dwi.nii.gz" "$MAIN_SC_SIFT2" \
    -tck_weights_in "${DWI_DIR}/sift2_weights.txt" \
    "${CONNECTOME_SCALE_ARGS[@]}" \
    -symmetric -zero_diagonal -assignment_radial_search "$MAIN_RADIAL_SEARCH" -nthreads "$NTHREADS"
fi

# 如果计数版 SC 矩阵还不存在，则生成未加权的 streamline count connectome。
if [[ ! -f "$MAIN_SC_COUNT" ]]; then
  tck2connectome "${DWI_DIR}/tracks.tck" "${DWI_DIR}/atlas_in_dwi.nii.gz" "$MAIN_SC_COUNT" \
    "${CONNECTOME_SCALE_ARGS[@]}" \
    -symmetric -zero_diagonal -assignment_radial_search "$MAIN_RADIAL_SEARCH" -nthreads "$NTHREADS"
fi

# 额外生成 4 mm 的对比实验加权 connectome。
if [[ ! -f "$COMPARE_SC_SIFT2" ]]; then
  tck2connectome "${DWI_DIR}/tracks.tck" "${DWI_DIR}/atlas_in_dwi.nii.gz" "$COMPARE_SC_SIFT2" \
    -tck_weights_in "${DWI_DIR}/sift2_weights.txt" \
    "${CONNECTOME_SCALE_ARGS[@]}" \
    -symmetric -zero_diagonal -assignment_radial_search "$COMPARE_RADIAL_SEARCH" -nthreads "$NTHREADS"
fi

# 额外生成 4 mm 的对比实验计数矩阵。
if [[ ! -f "$COMPARE_SC_COUNT" ]]; then
  tck2connectome "${DWI_DIR}/tracks.tck" "${DWI_DIR}/atlas_in_dwi.nii.gz" "$COMPARE_SC_COUNT" \
    "${CONNECTOME_SCALE_ARGS[@]}" \
    -symmetric -zero_diagonal -assignment_radial_search "$COMPARE_RADIAL_SEARCH" -nthreads "$NTHREADS"
fi

# 输出 2 mm 和 4 mm 的矩阵对比图，便于快速观察 STN 等小核团受搜索半径影响的程度。
if [[ ! -f "$COMPARE_RADIAL_PNG" ]]; then
  "$PYTHON_BIN" "${UTILS_DIR}/compare_connectome_radial.py" \
    --matrix-main "$MAIN_SC_SIFT2" \
    --matrix-compare "$COMPARE_SC_SIFT2" \
    --main-label "radial=2 (main)" \
    --compare-label "radial=4 (compare)" \
    --output "$COMPARE_RADIAL_PNG"
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
sc_count	${MAIN_SC_COUNT}
sc_sift2_radial4	${COMPARE_SC_SIFT2}
sc_count_radial4	${COMPARE_SC_COUNT}
compare_radial_png	${COMPARE_RADIAL_PNG}
scale_invnodevol_enabled	${CONNECTOME_SCALE_INVNODEVOL:-1}
assignment_radial_search_main	${MAIN_RADIAL_SEARCH}
assignment_radial_search_compare	${COMPARE_RADIAL_SEARCH}
EOF
