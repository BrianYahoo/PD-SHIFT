#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config
# 加载 FSL、ANTs 等工具环境。
setup_tools_env

BRAIN_EXTRACT_METHOD="${PHASE1_BRAIN_EXTRACT_METHOD}"
if [[ "${PHASE1_USE_BET:-1}" != "1" ]]; then
  BRAIN_EXTRACT_METHOD="none"
fi

# 检查当前 step 依赖的核心命令。
require_cmd N4BiasFieldCorrection
require_cmd fslmaths
case "${BRAIN_EXTRACT_METHOD}" in
  synthstrip)
    require_cmd mri_synthstrip
    ;;
  bet)
    require_cmd bet
    ;;
  none)
    ;;
  *)
    die "Unsupported PHASE1_BRAIN_EXTRACT_METHOD: ${BRAIN_EXTRACT_METHOD}"
    ;;
esac

# 定义当前 step 的核心输入输出。
STEP1_MANIFEST="${PHASE1_ANAT_STEP1_DIR}/manifest.tsv"
T1_INPUT="${PHASE0_INIT_STEP1_DIR}/t1.nii.gz"
T1_N4="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
T1_BIASFIELD="${PHASE1_ANAT_STEP1_DIR}/t1_biasfield.nii.gz"
T1_ORI_STALE="${PHASE1_ANAT_STEP1_DIR}/t1_ori.nii.gz"
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
T1_MASK="${PHASE1_ANAT_STEP1_DIR}/t1_brain_mask.nii.gz"
T1_FS_XMASK="${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_xmask.nii.gz"
T1_FS_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_brain.nii.gz"

images_share_grid() {
  local ref_path="$1"
  local test_path="$2"
  "${PYTHON_BIN}" - "${ref_path}" "${test_path}" <<'PY' >/dev/null 2>&1
import sys
import nibabel as nib
import numpy as np

ref = nib.load(sys.argv[1])
test = nib.load(sys.argv[2])
same_shape = tuple(ref.shape[:3]) == tuple(test.shape[:3])
same_affine = np.allclose(ref.affine, test.affine, atol=1e-4)
raise SystemExit(0 if same_shape and same_affine else 1)
PY
}

step1_outputs_ready() {
  [[ -f "${STEP1_MANIFEST}" && -f "${T1_N4}" && -f "${T1_BRAIN}" && -f "${T1_MASK}" && -f "${T1_FS_XMASK}" && -f "${T1_FS_BRAIN}" ]] || return 1
  images_share_grid "${T1_INPUT}" "${T1_N4}" || return 1
  images_share_grid "${T1_N4}" "${T1_BRAIN}" || return 1
  images_share_grid "${T1_N4}" "${T1_MASK}" || return 1
  images_share_grid "${T1_N4}" "${T1_FS_XMASK}" || return 1
  images_share_grid "${T1_N4}" "${T1_FS_BRAIN}" || return 1
}

# 输出当前 step 的开始日志。
log "[phase1_anat] Step1 brain extract for ${SUBJECT_ID}"

# `t1_ori` 已经前移到 phase0_init；这里如果残留旧文件，直接删除避免后续混淆。
rm -f "${T1_ORI_STALE}"

# 如果 phase0_init 重新导入/重采样了 T1，旧的 N4 和脑提取结果不能继续复用。
if [[ -f "${T1_N4}" ]] && ! images_share_grid "${T1_INPUT}" "${T1_N4}"; then
  rm -f "${T1_N4}" \
    "${T1_BIASFIELD}" \
    "${T1_BRAIN}" \
    "${T1_MASK}" \
    "${T1_FS_XMASK}" \
    "${T1_FS_BRAIN}" \
    "${STEP1_MANIFEST}"
fi

# 如果当前 step 的主要结果都已存在，则直接跳过。
if step1_outputs_ready; then
  log "[phase1_anat] Step1 already done for ${SUBJECT_ID}"
  exit 0
fi

# 对个体原生 T1 做偏场校正，给后续脑提取和 FreeSurfer 提供稳定输入。
if [[ ! -f "${T1_N4}" ]]; then
  N4BiasFieldCorrection -d 3 -i "${T1_INPUT}" -o "[${T1_N4},${T1_BIASFIELD}]" >"${PHASE1_ANAT_STEP1_DIR}/n4.log" 2>&1
fi

ORIGINAL_INPUT_ZOOMS_MM="$("${PYTHON_BIN}" - "${T1_INPUT}" <<'PY'
import sys
import nibabel as nib
img = nib.load(sys.argv[1])
zooms = img.header.get_zooms()[:3]
print(",".join(f"{float(z):.6f}" for z in zooms))
PY
)"

# 如果重采样后的 T1 与旧的脑掩膜/brain/xmask 网格不一致，则删除旧结果后重建。
for derived_nifti in "${T1_BRAIN}" "${T1_MASK}" "${T1_FS_XMASK}" "${T1_FS_BRAIN}"; do
  if [[ -f "${derived_nifti}" ]]; then
    if ! nifti_is_readable "${derived_nifti}" || ! images_share_grid "${T1_N4}" "${derived_nifti}"; then
      rm -f "${derived_nifti}"
    fi
  fi
done

# 脑提取方法由 dataset config 决定，流程代码不再直接判断 dataset 名称。
case "${BRAIN_EXTRACT_METHOD}" in
  synthstrip)
    if [[ ! -f "${T1_BRAIN}" || ! -f "${T1_MASK}" ]]; then
      mri_synthstrip -i "${T1_N4}" -o "${T1_BRAIN}" -m "${T1_MASK}" >"${PHASE1_ANAT_STEP1_DIR}/synthstrip.log" 2>&1
    fi
    ;;
  bet)
    if [[ ! -f "${T1_BRAIN}" ]]; then
      bet "${T1_N4}" "${T1_BRAIN}" -R -f "${PHASE1_BET_F}" -m >"${PHASE1_ANAT_STEP1_DIR}/bet.log" 2>&1
    fi
    ;;
  none)
    if [[ ! -f "${T1_BRAIN}" ]]; then
      cp -f "${T1_N4}" "${T1_BRAIN}"
    fi
    ;;
esac

# 生成个体原生空间脑掩膜，供后续配准和 QC 使用。
if [[ ! -f "${T1_MASK}" ]]; then
  fslmaths "${T1_BRAIN}" -bin "${T1_MASK}"
fi

# 为 FreeSurfer 单独准备一个更宽松的 xmask，避免掩膜过紧时截断胼胝体附近白质。
if [[ ! -f "${T1_FS_XMASK}" ]]; then
  cp -f "${T1_MASK}" "${T1_FS_XMASK}"
  fs_xmask_dilations="${PHASE1_FS_XMASK_DILATIONS:-2}"
  if [[ "${fs_xmask_dilations}" =~ ^[0-9]+$ ]] && (( fs_xmask_dilations > 0 )); then
    for ((i = 0; i < fs_xmask_dilations; i++)); do
      fslmaths "${T1_FS_XMASK}" -dilM "${T1_FS_XMASK}"
    done
  fi
  fslmaths "${T1_FS_XMASK}" -bin "${T1_FS_XMASK}"
fi

# 用更宽松的 FreeSurfer 专用 xmask 从偏场校正后的 T1 中生成 skull-stripped 强度图。
if [[ ! -f "${T1_FS_BRAIN}" ]]; then
  fslmaths "${T1_N4}" -mul "${T1_FS_XMASK}" "${T1_FS_BRAIN}"
fi

# 写出当前 step 的输出清单。
cat > "${STEP1_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
t1_input	${T1_INPUT}
t1_n4	${T1_N4}
t1_biasfield	${T1_BIASFIELD}
t1_brain	${T1_BRAIN}
t1_mask	${T1_MASK}
t1_freesurfer_xmask	${T1_FS_XMASK}
t1_freesurfer_brain	${T1_FS_BRAIN}
brain_extract_method	${BRAIN_EXTRACT_METHOD}
original_input_zooms_mm	${ORIGINAL_INPUT_ZOOMS_MM}
freesurfer_xmask_dilations	${PHASE1_FS_XMASK_DILATIONS:-2}
EOF

# 把当前 step 的关键体素结果链接到 stepview，便于直接核对。
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 1 1 "t1_n4" "${T1_N4}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 1 2 "t1_brain" "${T1_BRAIN}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 1 3 "t1_brain_mask" "${T1_MASK}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 1 4 "t1_freesurfer_xmask" "${T1_FS_XMASK}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 1 5 "t1_freesurfer_brain" "${T1_FS_BRAIN}"
