#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config
# 建立当前 trial 的输入输出目录。
setup_fmri_trial_context "${FMRI_TRIAL_NAME:-}"
# 加载 conda、FSL、FreeSurfer、ANTs 等工具环境。
setup_tools_env

# 检查当前 step 依赖的命令是否存在。
require_cmd "$PYTHON_BIN"
require_cmd epi_reg
require_cmd convert_xfm
require_cmd flirt
require_cmd fslmaths

# 定义当前 step 需要用到的结构像和分割文件。
T1_N4="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
T1_MASK="${PHASE1_ANAT_STEP1_DIR}/t1_brain_mask.nii.gz"
T2_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
ATLAS_T1="${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz"
ATLAS_LABELS="${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv"
VIS_BBR_DIR="${PHASE2_FMRI_TRIAL_VIS_DIR}/bbr"
VIS_BBR_DONE="${VIS_BBR_DIR}/split_overlay.done"
VIS_BBR_FRAMES="10,20,30,40,50,60,70,80,90,100"
VIS_BBR_FIRST_FRAME="${VIS_BBR_FRAMES%%,*}"
T2_IN_FUNC="${FMRI_DIR}/t2_in_func.nii.gz"

bbr_visualizations_ready() {
  local frame=""
  # 完成判定必须同时满足：
  # 1) done 标记存在；
  # 2) 旧版 t1/t2 目录不存在；
  # 3) 新版 atlas/subcortex PNG 在所有配置帧都补齐。
  # 这样 split_overlay.done 就不会再和真实 PNG 状态脱钩。
  [[ -f "${VIS_BBR_DONE}" ]] || return 1
  compgen -G "${VIS_BBR_DIR}"/t=*/t1 > /dev/null && return 1
  compgen -G "${VIS_BBR_DIR}"/t=*/t2 > /dev/null && return 1
  IFS=',' read -r -a _frames <<< "${VIS_BBR_FRAMES}"
  for frame in "${_frames[@]}"; do
    compgen -G "${VIS_BBR_DIR}/t=${frame}/atlas/z=*.png" > /dev/null || return 1
    compgen -G "${VIS_BBR_DIR}/t=${frame}/subcortex/AC/z=*.png" > /dev/null || return 1
  done
  return 0
}

reset_bbr_visualizations() {
  # 只清理可视化层，不动 func/anat 的真实配准结果。
  rm -f "${VIS_BBR_DONE}"
  rm -rf "${VIS_BBR_DIR}"/t=*/t1 "${VIS_BBR_DIR}"/t=*/t2
}

# 回填 stepview 中的 BBR 参考像。
link_step_product_nifti 5 1 "bbr_reference" "${FMRI_DIR}/func_mean.nii.gz"

# 如果所有配准和掩膜结果都已存在且关键 NIfTI 可读，则直接回填 stepview 并跳过。
if [[ -f "${FMRI_DIR}/bbr.mat" && -f "${FMRI_DIR}/t1_to_func.mat" ]] \
  && nifti_is_readable "${FMRI_DIR}/atlas_in_func.nii.gz" \
  && nifti_is_readable "${FMRI_DIR}/gs_mask_func.nii.gz" \
  && nifti_is_readable "${FMRI_DIR}/wm_mask_func.nii.gz" \
  && nifti_is_readable "${FMRI_DIR}/csf_mask_func.nii.gz" \
  && bbr_visualizations_ready; then
  link_step_product_nifti 5 2 "atlas_in_func" "${FMRI_DIR}/atlas_in_func.nii.gz"
  link_step_product_nifti 5 3 "global_mask" "${FMRI_DIR}/gs_mask_func.nii.gz"
  link_step_product_nifti 5 4 "wm_mask" "${FMRI_DIR}/wm_mask_func.nii.gz"
  link_step_product_nifti 5 5 "csf_mask" "${FMRI_DIR}/csf_mask_func.nii.gz"
  log "[phase2_fmri] Step5 already done for ${SUBJECT_ID} ${FMRI_TRIAL_NAME}"
  exit 0
fi

if [[ -f "${VIS_BBR_DONE}" ]] || compgen -G "${VIS_BBR_DIR}"/t=* > /dev/null || compgen -G "${VIS_BBR_DIR}"/t=*/t1 > /dev/null || compgen -G "${VIS_BBR_DIR}"/t=*/t2 > /dev/null; then
  # 只要检测到旧残留，就先回到“未完成”状态，强制重画，避免半新半旧目录混在一起。
  reset_bbr_visualizations
fi

# 如果功能像到 T1 的白质分割还不存在，则先从 aparc+aseg 里提取白质标签。
if [[ ! -f "${FMRI_DIR}/wmseg_t1.nii.gz" ]]; then
  "$PYTHON_BIN" - "$APARC_ASEG" "${FMRI_DIR}/wmseg_t1.nii.gz" <<'PY'
import nibabel as nib
import numpy as np
import sys

img = nib.load(sys.argv[1])
seg = np.asarray(img.dataobj, dtype=np.int32)
wm_labels = [2, 41, 7, 46, 16]
mask = np.isin(seg, wm_labels).astype(np.uint8)
nib.save(nib.Nifti1Image(mask, img.affine, img.header), sys.argv[2])
PY
fi

# 使用均值功能像和白质边界执行 BBR。
if [[ ! -f "${FMRI_DIR}/bbr.mat" ]]; then
  epi_reg \
    --epi="${FMRI_DIR}/func_mean.nii.gz" \
    --t1="$T1_N4" \
    --t1brain="$T1_BRAIN" \
    --wmseg="${FMRI_DIR}/wmseg_t1.nii.gz" \
    --out="${FMRI_DIR}/bbr" >"${FMRI_DIR}/epi_reg.log" 2>&1
fi

# 求出从 T1 到功能像空间的逆矩阵。
if [[ ! -f "${FMRI_DIR}/t1_to_func.mat" ]]; then
  convert_xfm -omat "${FMRI_DIR}/t1_to_func.mat" -inverse "${FMRI_DIR}/bbr.mat"
fi

# 将 custom atlas 投到功能像空间。
if [[ ! -f "${FMRI_DIR}/atlas_in_func.nii.gz" ]]; then
  flirt -in "$ATLAS_T1" -ref "${FMRI_DIR}/func_mean.nii.gz" -out "${FMRI_DIR}/atlas_in_func.nii.gz" -applyxfm -init "${FMRI_DIR}/t1_to_func.mat" -interp nearestneighbour >"${FMRI_DIR}/flirt_atlas_to_func.log" 2>&1
fi
link_step_product_nifti 5 2 "atlas_in_func" "${FMRI_DIR}/atlas_in_func.nii.gz"

if [[ -f "${T2_BRAIN}" && ! -f "${T2_IN_FUNC}" ]]; then
  flirt -in "${T2_BRAIN}" -ref "${FMRI_DIR}/func_mean.nii.gz" -out "${T2_IN_FUNC}" -applyxfm -init "${FMRI_DIR}/t1_to_func.mat" -interp trilinear >"${FMRI_DIR}/flirt_t2_to_func.log" 2>&1
fi
if [[ -f "${T2_IN_FUNC}" ]]; then
  link_step_product_nifti 5 6 "t2_in_func" "${T2_IN_FUNC}"
fi

# 将全脑掩膜投到功能像空间，后续用于全脑信号和可视化。
if [[ ! -f "${FMRI_DIR}/gs_mask_func.nii.gz" ]]; then
  flirt -in "$T1_MASK" -ref "${FMRI_DIR}/func_mean.nii.gz" -out "${FMRI_DIR}/gs_mask_func_raw.nii.gz" -applyxfm -init "${FMRI_DIR}/t1_to_func.mat" -interp nearestneighbour >"${FMRI_DIR}/flirt_gs_to_func.log" 2>&1
  fslmaths "${FMRI_DIR}/gs_mask_func_raw.nii.gz" -thr 0.5 -bin "${FMRI_DIR}/gs_mask_func.nii.gz"
fi
link_step_product_nifti 5 3 "global_mask" "${FMRI_DIR}/gs_mask_func.nii.gz"

# 如果 T1 空间的 WM/CSF 掩膜还不存在，则先从 aparc+aseg 提取。
if [[ ! -f "${FMRI_DIR}/wm_mask_t1.nii.gz" || ! -f "${FMRI_DIR}/csf_mask_t1.nii.gz" ]]; then
  "$PYTHON_BIN" - "$APARC_ASEG" "${FMRI_DIR}/wm_mask_t1.nii.gz" "${FMRI_DIR}/csf_mask_t1.nii.gz" <<'PY'
import nibabel as nib
import numpy as np
import sys

img = nib.load(sys.argv[1])
seg = np.asarray(img.dataobj, dtype=np.int32)
wm = np.isin(seg, [2, 41, 7, 46, 16]).astype(np.uint8)
csf = np.isin(seg, [4, 5, 14, 15, 24, 31, 43, 44, 63]).astype(np.uint8)
nib.save(nib.Nifti1Image(wm, img.affine, img.header), sys.argv[2])
nib.save(nib.Nifti1Image(csf, img.affine, img.header), sys.argv[3])
PY
fi

# 将 WM 掩膜投到功能像空间。
if [[ ! -f "${FMRI_DIR}/wm_mask_func.nii.gz" ]]; then
  flirt -in "${FMRI_DIR}/wm_mask_t1.nii.gz" -ref "${FMRI_DIR}/func_mean.nii.gz" -out "${FMRI_DIR}/wm_mask_func_raw.nii.gz" -applyxfm -init "${FMRI_DIR}/t1_to_func.mat" -interp nearestneighbour >"${FMRI_DIR}/flirt_wm_to_func.log" 2>&1
  fslmaths "${FMRI_DIR}/wm_mask_func_raw.nii.gz" -thr 0.5 -bin "${FMRI_DIR}/wm_mask_func.nii.gz"
fi
link_step_product_nifti 5 4 "wm_mask" "${FMRI_DIR}/wm_mask_func.nii.gz"

# 将 CSF 掩膜投到功能像空间。
if [[ ! -f "${FMRI_DIR}/csf_mask_func.nii.gz" ]]; then
  flirt -in "${FMRI_DIR}/csf_mask_t1.nii.gz" -ref "${FMRI_DIR}/func_mean.nii.gz" -out "${FMRI_DIR}/csf_mask_func_raw.nii.gz" -applyxfm -init "${FMRI_DIR}/t1_to_func.mat" -interp nearestneighbour >"${FMRI_DIR}/flirt_csf_to_func.log" 2>&1
  fslmaths "${FMRI_DIR}/csf_mask_func_raw.nii.gz" -thr 0.5 -bin "${FMRI_DIR}/csf_mask_func.nii.gz"
fi
link_step_product_nifti 5 5 "csf_mask" "${FMRI_DIR}/csf_mask_func.nii.gz"

# 在 BBR 完成后，把图谱叠加到若干时间点的功能像上，便于检查 atlas 投影是否准确。
mkdir -p "${VIS_BBR_DIR}"
"${PYTHON_BIN}" "${UTILS_DIR}/shared/visualization/visualize_registration_overlay.py" \
  --base "${FMRI_DIR}/func_mc.nii.gz" \
  --atlas "${FMRI_DIR}/atlas_in_func.nii.gz" \
  --labels-tsv "${ATLAS_LABELS}" \
  --out-dir "${VIS_BBR_DIR}" \
  --frames "${VIS_BBR_FRAMES}" \
  --split-subdirs
touch "${VIS_BBR_DONE}"
