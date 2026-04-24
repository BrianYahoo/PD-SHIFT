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
require_cmd fslmaths
require_cmd img2imgcoord
require_cmd mrcalc
require_cmd 5ttgen
require_cmd 5tt2gmwmi
require_cmd mrconvert
require_cmd "$PYTHON_BIN"

STEP4_LOG="${DWI_DIR}/step4_registration.log"

# 定义结构像和 atlas 相关输入。
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
T2_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
ATLAS_T1="${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz"
ATLAS_LABELS="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"
VIS_REG_DIR="${PHASE3_DWI_VIS_DIR}/registration"
VIS_REG_DONE="${VIS_REG_DIR}/split_overlay.done"
T2_IN_DWI="${DWI_DIR}/t2_in_dwi.nii.gz"
FIVETT_SCRATCH_DIR="${DWI_DIR}/scratch_5ttgen"
ATLAS_SMALL_NUCLEI_SCRATCH_DIR="${DWI_DIR}/scratch_small_nuclei_repair"
ATLAS_SMALL_NUCLEI_REPORT="${DWI_DIR}/atlas_small_nuclei_repair.json"

atlas_small_nuclei_ready() {
  if [[ "${DWI_ATLAS_PRESERVE_SMALL_NUCLEI:-1}" != "1" ]]; then
    return 0
  fi
  [[ -f "${DWI_DIR}/atlas_in_dwi.nii.gz" && -f "${ATLAS_T1}" && -f "${ATLAS_SMALL_NUCLEI_REPORT}" ]] || return 1
  "${PYTHON_BIN}" - "${ATLAS_T1}" "${DWI_DIR}/atlas_in_dwi.nii.gz" "${DWI_SMALL_NUCLEI_PROTECTED_LABELS:-41,42,43,44,45,46,87,88}" <<'PY'
import sys
import nibabel as nib
import numpy as np

src = {int(v) for v in np.unique(np.asarray(nib.load(sys.argv[1]).dataobj)) if float(v) > 0}
tgt = {int(v) for v in np.unique(np.asarray(nib.load(sys.argv[2]).dataobj)) if float(v) > 0}
protected = [int(v.strip()) for v in sys.argv[3].split(",") if v.strip()]
for idx in protected:
    if idx in src and idx not in tgt:
        raise SystemExit(1)
raise SystemExit(0)
PY
}

atlas_in_dwi_requires_refresh() {
  [[ -f "${ATLAS_T1}" && -f "${DWI_DIR}/atlas_in_dwi.nii.gz" ]] || return 1
  "${PYTHON_BIN}" - "${ATLAS_T1}" "${DWI_DIR}/atlas_in_dwi.nii.gz" "${DWI_SMALL_NUCLEI_PROTECTED_LABELS:-41,42,43,44,45,46,87,88}" <<'PY'
import sys
import nibabel as nib
import numpy as np

src = {int(v) for v in np.unique(np.asarray(nib.load(sys.argv[1]).dataobj)) if float(v) > 0}
tgt = {int(v) for v in np.unique(np.asarray(nib.load(sys.argv[2]).dataobj)) if float(v) > 0}
protected = {int(v.strip()) for v in sys.argv[3].split(",") if v.strip()}
missing_nonprotected = sorted((src - tgt) - protected)
raise SystemExit(0 if missing_nonprotected else 1)
PY
}

dwi_visualizations_ready() {
  [[ -f "${VIS_REG_DONE}" ]] || return 1
  compgen -G "${VIS_REG_DIR}/dwi/atlas/z=*.png" > /dev/null || return 1
  compgen -G "${VIS_REG_DIR}/dwi/subcortex/AC/z=*.png" > /dev/null || return 1
}

# 如果 DWI 空间下的配准和 5TT 结果已经存在，则直接跳过。
if [[ -f "${DWI_DIR}/t1_to_dwi.mat" && -f "${DWI_DIR}/atlas_in_dwi.nii.gz" && -f "${DWI_DIR}/aparc+aseg_int.nii.gz" && -f "${DWI_DIR}/aparc+aseg_dwi.nii.gz" && -f "${DWI_DIR}/5tt_dwi.mif" && -f "${DWI_DIR}/gmwmi_seed.mif" && ( "${DWI_5TT_FIX_HYBRID_SUBCGM:-1}" != "1" || -f "${DWI_DIR}/5tt_subcgm_fix.json" ) ]] \
  && atlas_small_nuclei_ready \
  && dwi_visualizations_ready; then
  log "[phase3_dwi] Step4 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果整型版 aparc+aseg 还不存在，则先把分割取整，避免最近邻插值后出现小数。
if [[ ! -f "${DWI_DIR}/aparc+aseg_int.nii.gz" ]]; then
  run_logged "${STEP4_LOG}" mrcalc "$APARC_ASEG" 0.5 -add -floor "${DWI_DIR}/aparc+aseg_int.nii.gz" -force
fi

# 如果 T1 到 DWI 的刚体矩阵还不存在，则执行 6 自由度配准。
if [[ ! -f "${DWI_DIR}/t1_to_dwi.mat" ]]; then
  flirt -in "$T1_BRAIN" -ref "${DWI_DIR}/mean_b0.nii.gz" -omat "${DWI_DIR}/t1_to_dwi.mat" -dof 6 -cost normmi >"${DWI_DIR}/flirt_t1_to_dwi.log" 2>&1
fi

# 如果 custom atlas 还没投到 DWI 空间，则执行最近邻投影。
if atlas_in_dwi_requires_refresh; then
  rm -f "${DWI_DIR}/atlas_in_dwi.nii.gz" "${ATLAS_SMALL_NUCLEI_REPORT}" "${VIS_REG_DONE}"
fi

if [[ ! -f "${DWI_DIR}/atlas_in_dwi.nii.gz" ]]; then
  flirt -in "$ATLAS_T1" -ref "${DWI_DIR}/mean_b0.nii.gz" -out "${DWI_DIR}/atlas_in_dwi.nii.gz" -applyxfm -init "${DWI_DIR}/t1_to_dwi.mat" -interp nearestneighbour >"${DWI_DIR}/flirt_atlas_to_dwi.log" 2>&1
fi

if [[ "${DWI_ATLAS_PRESERVE_SMALL_NUCLEI:-1}" == "1" ]] && ! atlas_small_nuclei_ready; then
  mkdir -p "${ATLAS_SMALL_NUCLEI_SCRATCH_DIR}"
  rm -f "${ATLAS_SMALL_NUCLEI_REPORT}"
  IFS=',' read -r -a protected_small_labels <<< "${DWI_SMALL_NUCLEI_PROTECTED_LABELS:-41,42,43,44,45,46,87,88}"
  for label_idx in "${protected_small_labels[@]}"; do
    label_idx="${label_idx//[[:space:]]/}"
    [[ -n "${label_idx}" ]] || continue
    source_mask="${ATLAS_SMALL_NUCLEI_SCRATCH_DIR}/label_${label_idx}_src.nii.gz"
    work_mask="${ATLAS_SMALL_NUCLEI_SCRATCH_DIR}/label_${label_idx}_work.nii.gz"
    target_mask="${ATLAS_SMALL_NUCLEI_SCRATCH_DIR}/label_${label_idx}_prob.nii.gz"
    run_logged "${STEP4_LOG}" fslmaths "${ATLAS_T1}" -thr "${label_idx}" -uthr "${label_idx}" -bin "${source_mask}"
    cp -f "${source_mask}" "${work_mask}"
    rm -f "${target_mask}"
    for dil_iter in 0 1 2 3 4; do
      if [[ "${dil_iter}" -gt 0 ]]; then
        run_logged "${STEP4_LOG}" fslmaths "${work_mask}" -dilM "${work_mask}"
      fi
      flirt -in "${work_mask}" \
        -ref "${DWI_DIR}/mean_b0.nii.gz" \
        -out "${target_mask}" \
        -applyxfm \
        -init "${DWI_DIR}/t1_to_dwi.mat" \
        -interp nearestneighbour >"${ATLAS_SMALL_NUCLEI_SCRATCH_DIR}/flirt_label_${label_idx}.log" 2>&1
      if "${PYTHON_BIN}" - "${target_mask}" <<'PY' >/dev/null 2>&1
import sys
import nibabel as nib
import numpy as np

data = np.asarray(nib.load(sys.argv[1]).dataobj)
raise SystemExit(0 if np.count_nonzero(data) > 0 else 1)
PY
      then
        break
      fi
    done
  done
  "${PYTHON_BIN}" "${UTILS_DIR}/phase3_dwi/step4/preserve_small_nuclei_labels.py" \
    --source-atlas "${ATLAS_T1}" \
    --target-atlas "${DWI_DIR}/atlas_in_dwi.nii.gz" \
    --transform-mat "${DWI_DIR}/t1_to_dwi.mat" \
    --labels-tsv "${ATLAS_LABELS}" \
    --candidate-dir "${ATLAS_SMALL_NUCLEI_SCRATCH_DIR}" \
    --protected-labels "${DWI_SMALL_NUCLEI_PROTECTED_LABELS:-41,42,43,44,45,46,87,88}" \
    --output "${DWI_DIR}/atlas_in_dwi.fixed.nii.gz" \
    --report "${ATLAS_SMALL_NUCLEI_REPORT}" >>"${STEP4_LOG}" 2>&1
  mv -f "${DWI_DIR}/atlas_in_dwi.fixed.nii.gz" "${DWI_DIR}/atlas_in_dwi.nii.gz"
  rm -rf "${ATLAS_SMALL_NUCLEI_SCRATCH_DIR}"
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

# 在调用 5ttgen 前，必须确认 DWI 空间分割已经真实存在，避免 MRtrix 在工作目录落根级临时目录后才失败。
[[ -f "${DWI_DIR}/aparc+aseg_dwi.nii.gz" ]] || die "Missing DWI-space aparc+aseg before 5ttgen: ${DWI_DIR}/aparc+aseg_dwi.nii.gz"

# 如果 5TT 组织分型图还不存在，则基于 DWI 空间的 FreeSurfer 分割生成 5TT。
if [[ ! -f "${DWI_DIR}/5tt_dwi.mif" ]]; then
  mkdir -p "${FIVETT_SCRATCH_DIR}"
  run_logged "${STEP4_LOG}" 5ttgen freesurfer "${DWI_DIR}/aparc+aseg_dwi.nii.gz" "${DWI_DIR}/5tt_dwi.mif" -lut "${DWI_DIR}/FreeSurferColorLUT_mrtrix.txt" -nocrop -nthreads "$NTHREADS" -scratch "${FIVETT_SCRATCH_DIR}"
  rm -rf "${FIVETT_SCRATCH_DIR}"
fi

# 如果开启 hybrid atlas 修补，则把 STN/GPi 位置从 WM 改到 subcortical GM，避免 ACT 在深部靶点处截断。
if [[ "${DWI_5TT_FIX_HYBRID_SUBCGM:-1}" == "1" && ! -f "${DWI_DIR}/5tt_subcgm_fix.json" ]]; then
  run_logged "${STEP4_LOG}" mrconvert "${DWI_DIR}/5tt_dwi.mif" "${DWI_DIR}/5tt_dwi_raw.nii.gz" -force
  "$PYTHON_BIN" "${UTILS_DIR}/phase3_dwi/step4/repair_5tt_hybrid_subcgm.py" \
    --five-tt "${DWI_DIR}/5tt_dwi_raw.nii.gz" \
    --atlas "${DWI_DIR}/atlas_in_dwi.nii.gz" \
    --labels "${ATLAS_LABELS}" \
    --output "${DWI_DIR}/5tt_dwi_fixed.nii.gz" \
    --output-qc "${DWI_DIR}/5tt_subcgm_fix.json" >>"${STEP4_LOG}" 2>&1
  run_logged "${STEP4_LOG}" mrconvert "${DWI_DIR}/5tt_dwi_fixed.nii.gz" "${DWI_DIR}/5tt_dwi.mif" -force
fi

# 如果灰白质交界种子还不存在，则从 5TT 中提取 gmwmi。
if [[ ! -f "${DWI_DIR}/gmwmi_seed.mif" ]]; then
  run_logged "${STEP4_LOG}" 5tt2gmwmi "${DWI_DIR}/5tt_dwi.mif" "${DWI_DIR}/gmwmi_seed.mif"
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
  --split-subdirs >>"${STEP4_LOG}" 2>&1
touch "${VIS_REG_DONE}"
