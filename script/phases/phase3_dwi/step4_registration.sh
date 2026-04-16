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
require_cmd flirt
require_cmd mrcalc
require_cmd 5ttgen
require_cmd 5tt2gmwmi
require_cmd mrconvert
require_cmd "$PYTHON_BIN"

# 定义结构像和 atlas 相关输入。
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
T2_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
ATLAS_T1="${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz"
ATLAS_LABELS="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"
VIS_REG_DIR="${PHASE3_DWI_VIS_DIR}/registration"
VIS_REG_DONE="${VIS_REG_DIR}/split_overlay.done"
T2_IN_DWI="${DWI_DIR}/t2_in_dwi.nii.gz"

dwi_visualizations_ready() {
  [[ -f "${VIS_REG_DONE}" ]] || return 1
  compgen -G "${VIS_REG_DIR}/dwi/atlas/z=*.png" > /dev/null || return 1
  compgen -G "${VIS_REG_DIR}/dwi/subcortex/AC/z=*.png" > /dev/null || return 1
}

# 如果 DWI 空间下的配准和 5TT 结果已经存在，则直接跳过。
if [[ -f "${DWI_DIR}/t1_to_dwi.mat" && -f "${DWI_DIR}/atlas_in_dwi.nii.gz" && -f "${DWI_DIR}/aparc+aseg_int.nii.gz" && -f "${DWI_DIR}/aparc+aseg_dwi.nii.gz" && -f "${DWI_DIR}/5tt_dwi.mif" && -f "${DWI_DIR}/gmwmi_seed.mif" && ( "${DWI_5TT_FIX_HYBRID_SUBCGM:-1}" != "1" || -f "${DWI_DIR}/5tt_subcgm_fix.json" ) && dwi_visualizations_ready ]]; then
  log "[phase3_dwi] Step4 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果整型版 aparc+aseg 还不存在，则先把分割取整，避免最近邻插值后出现小数。
if [[ ! -f "${DWI_DIR}/aparc+aseg_int.nii.gz" ]]; then
  mrcalc "$APARC_ASEG" 0.5 -add -floor "${DWI_DIR}/aparc+aseg_int.nii.gz" -force
fi

# 如果 T1 到 DWI 的刚体矩阵还不存在，则执行 6 自由度配准。
if [[ ! -f "${DWI_DIR}/t1_to_dwi.mat" ]]; then
  flirt -in "$T1_BRAIN" -ref "${DWI_DIR}/mean_b0.nii.gz" -omat "${DWI_DIR}/t1_to_dwi.mat" -dof 6 -cost normmi >"${DWI_DIR}/flirt_t1_to_dwi.log" 2>&1
fi

# 如果 custom atlas 还没投到 DWI 空间，则执行最近邻投影。
if [[ ! -f "${DWI_DIR}/atlas_in_dwi.nii.gz" ]]; then
  flirt -in "$ATLAS_T1" -ref "${DWI_DIR}/mean_b0.nii.gz" -out "${DWI_DIR}/atlas_in_dwi.nii.gz" -applyxfm -init "${DWI_DIR}/t1_to_dwi.mat" -interp nearestneighbour >"${DWI_DIR}/flirt_atlas_to_dwi.log" 2>&1
fi

if [[ -f "${T2_BRAIN}" && ! -f "${T2_IN_DWI}" ]]; then
  flirt -in "${T2_BRAIN}" -ref "${DWI_DIR}/mean_b0.nii.gz" -out "${T2_IN_DWI}" -applyxfm -init "${DWI_DIR}/t1_to_dwi.mat" -interp trilinear >"${DWI_DIR}/flirt_t2_to_dwi.log" 2>&1
fi

# 如果 aparc+aseg 还没投到 DWI 空间，则执行最近邻投影。
if [[ ! -f "${DWI_DIR}/aparc+aseg_dwi.nii.gz" ]]; then
  flirt -in "${DWI_DIR}/aparc+aseg_int.nii.gz" -ref "${DWI_DIR}/mean_b0.nii.gz" -out "${DWI_DIR}/aparc+aseg_dwi.nii.gz" -applyxfm -init "${DWI_DIR}/t1_to_dwi.mat" -interp nearestneighbour >"${DWI_DIR}/flirt_aparc_to_dwi.log" 2>&1
fi

# 如果 MRtrix 可读取的 LUT 还不存在，则把 FreeSurfer LUT 转成制表符格式。
if [[ ! -f "${DWI_DIR}/FreeSurferColorLUT_mrtrix.txt" ]]; then
  awk '
    /^[[:space:]]*#/ || NF==0 { print; next }
    NF>=6 { print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }
  ' "${FREESURFER_HOME}/FreeSurferColorLUT.txt" > "${DWI_DIR}/FreeSurferColorLUT_mrtrix.txt"
fi

# 如果 5TT 组织分型图还不存在，则基于 DWI 空间的 FreeSurfer 分割生成 5TT。
if [[ ! -f "${DWI_DIR}/5tt_dwi.mif" ]]; then
  5ttgen freesurfer "${DWI_DIR}/aparc+aseg_dwi.nii.gz" "${DWI_DIR}/5tt_dwi.mif" -lut "${DWI_DIR}/FreeSurferColorLUT_mrtrix.txt" -nocrop -nthreads "$NTHREADS"
fi

# 如果开启 hybrid atlas 修补，则把 STN/GPi 位置从 WM 改到 subcortical GM，避免 ACT 在深部靶点处截断。
if [[ "${DWI_5TT_FIX_HYBRID_SUBCGM:-1}" == "1" && ! -f "${DWI_DIR}/5tt_subcgm_fix.json" ]]; then
  mrconvert "${DWI_DIR}/5tt_dwi.mif" "${DWI_DIR}/5tt_dwi_raw.nii.gz" -force
  "$PYTHON_BIN" "${UTILS_DIR}/phase3_dwi/step4/repair_5tt_hybrid_subcgm.py" \
    --five-tt "${DWI_DIR}/5tt_dwi_raw.nii.gz" \
    --atlas "${DWI_DIR}/atlas_in_dwi.nii.gz" \
    --labels "${ATLAS_LABELS}" \
    --output "${DWI_DIR}/5tt_dwi_fixed.nii.gz" \
    --output-qc "${DWI_DIR}/5tt_subcgm_fix.json"
  mrconvert "${DWI_DIR}/5tt_dwi_fixed.nii.gz" "${DWI_DIR}/5tt_dwi.mif" -force
fi

# 如果灰白质交界种子还不存在，则从 5TT 中提取 gmwmi。
if [[ ! -f "${DWI_DIR}/gmwmi_seed.mif" ]]; then
  5tt2gmwmi "${DWI_DIR}/5tt_dwi.mif" "${DWI_DIR}/gmwmi_seed.mif"
fi

# 把图谱叠加到 DWI 的 mean_b0 上，逐层输出 PNG 便于检查结构空间配准质量。
mkdir -p "${VIS_REG_DIR}"
rm -rf "${VIS_REG_DIR}/dwi/t1" "${VIS_REG_DIR}/dwi/t2"
"${PYTHON_BIN}" "${UTILS_DIR}/shared/visualization/visualize_registration_overlay.py" \
  --base "${DWI_DIR}/mean_b0.nii.gz" \
  --atlas "${DWI_DIR}/atlas_in_dwi.nii.gz" \
  --labels-tsv "${ATLAS_LABELS}" \
  --out-dir "${VIS_REG_DIR}" \
  --frame-label dwi \
  --split-subdirs
touch "${VIS_REG_DONE}"
