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
if [[ "${PHASE1_LEADDBS_NATIVE_ENABLE:-0}" == "1" ]]; then
  setup_leaddbs_env
fi

# 检查当前 step 依赖的核心命令。
require_cmd "$PYTHON_BIN"
require_cmd fslmaths
if [[ "${PHASE1_LEADDBS_NATIVE_ENABLE:-0}" == "1" ]]; then
  [[ -x "${MATLAB_BIN}" ]] || die "MATLAB executable is unavailable for native Lead-DBS: ${MATLAB_BIN:-unset}"
else
  require_cmd antsRegistration
fi

# 定义当前 step 的核心输入输出。
STEP3_MANIFEST="${PHASE1_ANAT_STEP3_DIR}/manifest.tsv"
T1_NATIVE="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
T2_NATIVE="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz"
T2_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
MNI_BRAIN="${PHASE1_ANAT_STEP3_DIR}/mni2009b_brain.nii.gz"
MNI_T2_BRAIN="${PHASE1_ANAT_STEP3_DIR}/mni2009b_t2_brain.nii.gz"
MNI_SUBCORTICAL_MASK_NATIVE="${PHASE1_ANAT_STEP3_DIR}/mni2009b_subcortical_mask.nii.gz"
NATIVE_SUBCORTICAL_MASK="${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask.nii.gz"
DISTAL_MNI="${PHASE1_ANAT_STEP3_DIR}/distal6_mni.nii.gz"
DISTAL_LABELS="${PHASE1_ANAT_STEP3_DIR}/distal6_labels.tsv"
SN_MNI="${PHASE1_ANAT_STEP3_DIR}/sn2_mni.nii.gz"
SN_LABELS="${PHASE1_ANAT_STEP3_DIR}/sn2_labels.tsv"
REG_PREFIX="${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_"
REG_AFFINE="${REG_PREFIX}0GenericAffine.mat"
REG_WARP="${REG_PREFIX}1Warp.nii.gz"
REG_INV_WARP="${REG_PREFIX}1InverseWarp.nii.gz"
REG_ALT_WARP="${REG_PREFIX}0Warp.nii.gz"
REG_ALT_INV_WARP="${REG_PREFIX}0InverseWarp.nii.gz"
STEP3_FORWARD_AFFINE=""
STEP3_FORWARD_WARP=""
STEP3_INVERSE_WARP=""
STEP3_TRANSFORM_LAYOUT=""
STEP3_REGISTRATION_ENGINE="antsRegistration"
LEADDBS_NATIVE_DIR="${PHASE1_ANAT_STEP3_DIR}/leaddbs_native"
LEADDBS_NATIVE_LOG="${PHASE1_ANAT_STEP3_DIR}/leaddbs_native.log"
LEADDBS_NATIVE_SCRIPT="${LEADDBS_NATIVE_DIR}/run_leaddbs_native_step3.m"
LEADDBS_SUBJECT_TOKEN="sub-${SUBJECT_KEY}"
LEADDBS_COREG_ANAT_DIR="${LEADDBS_NATIVE_DIR}/coregistration/anat"
LEADDBS_NORMALIZATION_DIR="${LEADDBS_NATIVE_DIR}/normalization"
LEADDBS_NORMALIZATION_ANAT_DIR="${LEADDBS_NORMALIZATION_DIR}/anat"
LEADDBS_NORMALIZATION_XFM_DIR="${LEADDBS_NORMALIZATION_DIR}/transformations"
LEADDBS_NORMALIZATION_LOG_DIR="${LEADDBS_NORMALIZATION_DIR}/log"
LEADDBS_METHOD_LOG="${LEADDBS_NATIVE_DIR}/log/${LEADDBS_SUBJECT_TOKEN}_desc-methods.txt"
LEADDBS_T1_INPUT="${LEADDBS_COREG_ANAT_DIR}/${LEADDBS_SUBJECT_TOKEN}_ses-preop_space-anchorNative_desc-preproc_acq-iso_T1w.nii.gz"
LEADDBS_T2_INPUT="${LEADDBS_COREG_ANAT_DIR}/${LEADDBS_SUBJECT_TOKEN}_ses-preop_space-anchorNative_desc-preproc_acq-iso_T2w.nii.gz"
LEADDBS_NORM_T1="${LEADDBS_NORMALIZATION_ANAT_DIR}/${LEADDBS_SUBJECT_TOKEN}_ses-preop_space-MNI152NLin2009bAsym_desc-preproc_acq-iso_T1w.nii"
LEADDBS_NATIVE_TO_MNI_WARP="${LEADDBS_NORMALIZATION_XFM_DIR}/${LEADDBS_SUBJECT_TOKEN}_from-anchorNative_to-MNI152NLin2009bAsym_desc-ants.nii.gz"
LEADDBS_MNI_TO_NATIVE_WARP="${LEADDBS_NORMALIZATION_XFM_DIR}/${LEADDBS_SUBJECT_TOKEN}_from-MNI152NLin2009bAsym_to-anchorNative_desc-ants.nii.gz"
LEADDBS_NORMMETHOD_JSON="${LEADDBS_NORMALIZATION_LOG_DIR}/${LEADDBS_SUBJECT_TOKEN}_desc-normmethod.json"
LEADDBS_ANTSCMD_LOG="${LEADDBS_NORMALIZATION_LOG_DIR}/${LEADDBS_SUBJECT_TOKEN}_desc-antscmd.txt"

STEP3_USE_T2="0"
STEP3_REGISTRATION_MODE="single_t1_raw"
STEP3_REGISTRATION_REASON="t2_disabled"
if [[ "${PHASE1_T2_MULTICHANNEL_REG_ENABLE:-0}" == "1" && -f "${T2_BRAIN}" && -n "${MNI_T2:-}" && -f "${MNI_T2}" ]]; then
  STEP3_USE_T2="1"
  STEP3_REGISTRATION_MODE="multichannel_t1_t2_raw"
  STEP3_REGISTRATION_REASON="t1_t2_multichannel"
elif [[ "${PHASE1_T2_MULTICHANNEL_REG_ENABLE:-0}" == "1" && ! -f "${T2_BRAIN}" ]]; then
  STEP3_REGISTRATION_REASON="t2_missing"
elif [[ "${PHASE1_T2_MULTICHANNEL_REG_ENABLE:-0}" == "1" && ( -z "${MNI_T2:-}" || ! -f "${MNI_T2:-}" ) ]]; then
  STEP3_REGISTRATION_REASON="mni_t2_missing"
fi

STEP3_USE_MASK="0"
STEP3_MASK_MODE="none"
STEP3_MASK_REASON="mask_disabled"
if [[ "${PHASE1_SUBCORTICAL_MASK_ENABLE:-0}" == "1" && -n "${MNI_SUBCORTICAL_MASK:-}" && -f "${MNI_SUBCORTICAL_MASK}" ]]; then
  STEP3_USE_MASK="1"
  STEP3_MASK_MODE="dual_subcortical"
  STEP3_MASK_REASON="mni_and_native_subcortical"
elif [[ "${PHASE1_SUBCORTICAL_MASK_ENABLE:-0}" == "1" ]]; then
  STEP3_MASK_REASON="mni_mask_missing"
fi

STEP3_USE_AFFINE="${PHASE1_REG_AFFINE_ENABLE:-1}"
STEP3_AFFINE_REASON="config"
STEP3_USE_LEADDBS_NATIVE="${PHASE1_LEADDBS_NATIVE_ENABLE:-0}"
if [[ "${STEP3_USE_LEADDBS_NATIVE}" == "1" ]]; then
  STEP3_REGISTRATION_ENGINE="leaddbs_native"
fi

resolve_step3_transform_outputs() {
  STEP3_FORWARD_AFFINE=""
  STEP3_FORWARD_WARP=""
  STEP3_INVERSE_WARP=""
  STEP3_TRANSFORM_LAYOUT=""

  # antsRegistration 正常会给 affine + warp，但某些恢复场景可能只剩 composite warp。
  # 这里统一解析成下游固定要读的三个槽位，避免 step5/step6 直接绑定某一种文件布局。
  if [[ -f "${REG_AFFINE}" && -f "${REG_WARP}" ]]; then
    STEP3_FORWARD_AFFINE="${REG_AFFINE}"
    STEP3_FORWARD_WARP="${REG_WARP}"
    [[ -f "${REG_INV_WARP}" ]] && STEP3_INVERSE_WARP="${REG_INV_WARP}"
    STEP3_TRANSFORM_LAYOUT="affine_plus_warp"
    return 0
  fi

  if [[ ! -f "${REG_AFFINE}" && -f "${REG_WARP}" && -f "${REG_ALT_WARP}" ]]; then
    STEP3_FORWARD_WARP="${REG_WARP}"
    if [[ -f "${REG_INV_WARP}" ]]; then
      STEP3_INVERSE_WARP="${REG_INV_WARP}"
    elif [[ -f "${REG_ALT_INV_WARP}" ]]; then
      STEP3_INVERSE_WARP="${REG_ALT_INV_WARP}"
    fi
    STEP3_TRANSFORM_LAYOUT="composite_warp_only"
    return 0
  fi

  return 1
}

prepare_leaddbs_native_workspace() {
  rm -rf "${LEADDBS_NATIVE_DIR}"
  mkdir -p \
    "${LEADDBS_COREG_ANAT_DIR}" \
    "${LEADDBS_NORMALIZATION_ANAT_DIR}" \
    "${LEADDBS_NORMALIZATION_XFM_DIR}" \
    "${LEADDBS_NORMALIZATION_LOG_DIR}" \
    "${LEADDBS_NATIVE_DIR}/log"
  cp -f "${T1_NATIVE}" "${LEADDBS_T1_INPUT}"
  if [[ "${STEP3_USE_T2}" == "1" ]]; then
    cp -f "${T2_NATIVE}" "${LEADDBS_T2_INPUT}"
  else
    rm -f "${LEADDBS_T2_INPUT}"
  fi
}

write_leaddbs_native_matlab_script() {
  local use_t2="${STEP3_USE_T2}"
  cat > "${LEADDBS_NATIVE_SCRIPT}" <<EOF
restoredefaultpath;
addpath('${SPM12_HOME}');
addpath('${LEADDBS_HOME}');
ea_setpath;

subj = '${SUBJECT_KEY}';
work = '${LEADDBS_NATIVE_DIR}';
t1 = '${LEADDBS_T1_INPUT}';
t1norm = '${LEADDBS_NORM_T1}';
methodlog = '${LEADDBS_METHOD_LOG}';
forwardbase = '${LEADDBS_NORMALIZATION_XFM_DIR}/${LEADDBS_SUBJECT_TOKEN}_from-anchorNative_to-MNI152NLin2009bAsym_desc-';
inversebase = '${LEADDBS_NORMALIZATION_XFM_DIR}/${LEADDBS_SUBJECT_TOKEN}_from-MNI152NLin2009bAsym_to-anchorNative_desc-';
normmethod = '${LEADDBS_NORMMETHOD_JSON}';
logbase = '${LEADDBS_NORMALIZATION_LOG_DIR}/${LEADDBS_SUBJECT_TOKEN}_desc-norm';
spacedef = ea_getspacedef;

options = loadjson(fullfile('${LEADDBS_HOME}', 'common', 'uiprefs.json'));
options = ea_resolve_elspec(options);
options.prefs = ea_prefs(['sub-' subj]);
options.bids = struct();
options.bids.spacedef = spacedef;
options.overwriteapproved = 1;
options.normalize.do = 1;
options.normalize.method = 'ANTs (Avants 2008)';
options.leadprod = 'dbs';

options.subj = struct();
options.subj.subjId = subj;
options.subj.subjDir = work;
options.subj.methodLog = methodlog;
options.subj.AnchorModality = 'T1w';
options.subj.postopModality = 'None';
options.subj.coregDir = fullfile(work, 'coregistration');
options.subj.normDir = fullfile(work, 'normalization');
options.subj.logDir = fullfile(work, 'log');
options.subj.brainshiftDir = fullfile(work, 'brainshift');

options.subj.preopAnat = struct();
options.subj.preopAnat.T1w = struct( ...
    'raw', t1, ...
    'preproc', t1, ...
    'coreg', t1, ...
    'norm', t1norm ...
);

options.subj.coreg = struct();
options.subj.coreg.anat = struct();
options.subj.coreg.anat.preop = struct('T1w', t1);

options.subj.norm = struct();
options.subj.norm.anat = struct();
options.subj.norm.anat.preop = struct('T1w', t1norm);
options.subj.norm.transform = struct( ...
    'forwardBaseName', forwardbase, ...
    'inverseBaseName', inversebase ...
);
options.subj.norm.log = struct( ...
    'method', normmethod, ...
    'logBaseName', logbase ...
);

if strcmp('${use_t2}', '1')
    t2 = '${LEADDBS_T2_INPUT}';
    options.subj.preopAnat.T2w = struct( ...
        'raw', t2, ...
        'preproc', t2, ...
        'coreg', t2 ...
    );
    options.subj.coreg.anat.preop.T2w = t2;
end

try
    ea_normalize(options);
catch ME
    disp(getReport(ME, 'extended', 'hyperlinks', 'off'));
    exit(1);
end

if ~(exist('${LEADDBS_NATIVE_TO_MNI_WARP}', 'file') == 2 && exist('${LEADDBS_MNI_TO_NATIVE_WARP}', 'file') == 2)
    error('Lead-DBS native normalization finished without the expected transform outputs.');
end
exit(0);
EOF
}

run_leaddbs_native_registration() {
  prepare_leaddbs_native_workspace
  write_leaddbs_native_matlab_script
  "${MATLAB_BIN}" -batch "run('${LEADDBS_NATIVE_SCRIPT}');" >"${LEADDBS_NATIVE_LOG}" 2>&1
  [[ -f "${LEADDBS_MNI_TO_NATIVE_WARP}" ]] || die "Missing Lead-DBS MNI->native warp: ${LEADDBS_MNI_TO_NATIVE_WARP}"
  [[ -f "${LEADDBS_NATIVE_TO_MNI_WARP}" ]] || die "Missing Lead-DBS native->MNI warp: ${LEADDBS_NATIVE_TO_MNI_WARP}"

  rm -f "${REG_AFFINE}"
  cp -f "${LEADDBS_MNI_TO_NATIVE_WARP}" "${REG_WARP}"
  cp -f "${LEADDBS_MNI_TO_NATIVE_WARP}" "${REG_ALT_WARP}"
  cp -f "${LEADDBS_NATIVE_TO_MNI_WARP}" "${REG_INV_WARP}"
  cp -f "${LEADDBS_NATIVE_TO_MNI_WARP}" "${REG_ALT_INV_WARP}"
}

step3_outputs_ready() {
  local manifest_registration_engine=""
  local manifest_registration_mode=""
  local manifest_use_t2=""
  local manifest_mni_t2=""
  local manifest_mask_mode=""
  local manifest_use_mask=""
  local manifest_mask_path=""
  local manifest_use_affine=""
  local manifest_transform_layout=""
  local manifest_forward_affine=""
  local manifest_forward_warp=""
  local manifest_inverse_warp=""
  [[ -f "${STEP3_MANIFEST}" && -f "${MNI_BRAIN}" && -f "${DISTAL_MNI}" && -f "${DISTAL_LABELS}" && -f "${SN_MNI}" && -f "${SN_LABELS}" ]] || return 1
  resolve_step3_transform_outputs || return 1
  # Step3 的完成判定不只看变换文件是否存在，还要确认 manifest 记录的模式
  # 与当前 config 派生出来的模式完全一致，避免单通道/双通道或 masked/unmasked 结果串用。
  [[ -n "${STEP3_FORWARD_WARP}" && -f "${STEP3_FORWARD_WARP}" ]] || return 1
  [[ -z "${STEP3_FORWARD_AFFINE}" || -f "${STEP3_FORWARD_AFFINE}" ]] || return 1
  [[ -z "${STEP3_INVERSE_WARP}" || -f "${STEP3_INVERSE_WARP}" ]] || return 1
  manifest_registration_mode="$(read_manifest_value "${STEP3_MANIFEST}" "registration_mode")"
  manifest_registration_engine="$(read_manifest_value "${STEP3_MANIFEST}" "registration_engine")"
  manifest_use_t2="$(read_manifest_value "${STEP3_MANIFEST}" "registration_use_t2")"
  manifest_mni_t2="$(read_manifest_value "${STEP3_MANIFEST}" "mni_t2")"
  manifest_mask_mode="$(read_manifest_value "${STEP3_MANIFEST}" "registration_mask_mode")"
  manifest_use_mask="$(read_manifest_value "${STEP3_MANIFEST}" "registration_use_mask")"
  manifest_mask_path="$(read_manifest_value "${STEP3_MANIFEST}" "mni_subcortical_mask")"
  manifest_use_affine="$(read_manifest_value "${STEP3_MANIFEST}" "registration_use_affine")"
  manifest_transform_layout="$(read_manifest_value "${STEP3_MANIFEST}" "transform_layout")"
  manifest_forward_affine="$(read_manifest_value "${STEP3_MANIFEST}" "forward_affine")"
  manifest_forward_warp="$(read_manifest_value "${STEP3_MANIFEST}" "forward_warp")"
  manifest_inverse_warp="$(read_manifest_value "${STEP3_MANIFEST}" "inverse_warp")"
  [[ "${manifest_registration_engine}" == "${STEP3_REGISTRATION_ENGINE}" ]] || return 1
  [[ "${manifest_registration_mode}" == "${STEP3_REGISTRATION_MODE}" ]] || return 1
  [[ "${manifest_use_t2:-0}" == "${STEP3_USE_T2}" ]] || return 1
  [[ "${manifest_use_affine:-1}" == "${STEP3_USE_AFFINE}" ]] || return 1
  [[ "${manifest_transform_layout}" == "${STEP3_TRANSFORM_LAYOUT}" ]] || return 1
  [[ "${manifest_forward_affine}" == "${STEP3_FORWARD_AFFINE}" ]] || return 1
  [[ "${manifest_forward_warp}" == "${STEP3_FORWARD_WARP}" ]] || return 1
  [[ "${manifest_inverse_warp}" == "${STEP3_INVERSE_WARP}" ]] || return 1
  if [[ "${STEP3_USE_T2}" == "1" ]]; then
    [[ -f "${MNI_T2_BRAIN}" ]] || return 1
    [[ "${manifest_mni_t2}" == "${MNI_T2}" ]] || return 1
  fi
  [[ "${manifest_mask_mode}" == "${STEP3_MASK_MODE}" ]] || return 1
  [[ "${manifest_use_mask:-0}" == "${STEP3_USE_MASK}" ]] || return 1
  if [[ "${STEP3_USE_MASK}" == "1" ]]; then
    [[ -f "${MNI_SUBCORTICAL_MASK_NATIVE}" ]] || return 1
    [[ -f "${NATIVE_SUBCORTICAL_MASK}" ]] || return 1
    [[ "${manifest_mask_path}" == "${MNI_SUBCORTICAL_MASK}" ]] || return 1
  fi
}

reset_step3_outputs() {
  rm -f "${STEP3_MANIFEST}" \
    "${MNI_BRAIN}" \
    "${MNI_T2_BRAIN}" \
    "${MNI_SUBCORTICAL_MASK_NATIVE}" \
    "${NATIVE_SUBCORTICAL_MASK}" \
    "${DISTAL_MNI}" \
    "${DISTAL_LABELS}" \
    "${SN_MNI}" \
    "${SN_LABELS}" \
    "${REG_AFFINE}" \
    "${REG_WARP}" \
    "${REG_INV_WARP}" \
    "${REG_ALT_WARP}" \
    "${REG_ALT_INV_WARP}" \
    "${PHASE1_ANAT_STEP3_DIR}/ants_syn.log" \
    "${LEADDBS_NATIVE_LOG}"
  rm -rf "${LEADDBS_NATIVE_DIR}"
}

# 输出当前 step 的开始日志。这里按实际 registration engine 命名，
# 避免 native Lead-DBS 仍然打印成 SyN，造成并行日志阅读混淆。
if [[ "${STEP3_USE_LEADDBS_NATIVE}" == "1" ]]; then
  log "[phase1_anat] Step3 native Lead-DBS normalization for ${SUBJECT_ID}"
else
  log "[phase1_anat] Step3 subcortical SyN for ${SUBJECT_ID}"
fi
log "[phase1_anat] Step3 engine=${STEP3_REGISTRATION_ENGINE} mode=${STEP3_REGISTRATION_MODE} use_t2=${STEP3_USE_T2} use_mask=${STEP3_USE_MASK} use_affine=${STEP3_USE_AFFINE}"

if [[ -f "${STEP3_MANIFEST}" ]]; then
  manifest_registration_engine="$(read_manifest_value "${STEP3_MANIFEST}" "registration_engine")"
  manifest_registration_mode="$(read_manifest_value "${STEP3_MANIFEST}" "registration_mode")"
  manifest_use_t2="$(read_manifest_value "${STEP3_MANIFEST}" "registration_use_t2")"
  manifest_mni_t2="$(read_manifest_value "${STEP3_MANIFEST}" "mni_t2")"
  manifest_mask_mode="$(read_manifest_value "${STEP3_MANIFEST}" "registration_mask_mode")"
  manifest_use_mask="$(read_manifest_value "${STEP3_MANIFEST}" "registration_use_mask")"
  manifest_mask_path="$(read_manifest_value "${STEP3_MANIFEST}" "mni_subcortical_mask")"
  manifest_use_affine="$(read_manifest_value "${STEP3_MANIFEST}" "registration_use_affine")"
  if [[ "${manifest_registration_engine}" != "${STEP3_REGISTRATION_ENGINE}" || "${manifest_registration_mode}" != "${STEP3_REGISTRATION_MODE}" || "${manifest_use_t2:-0}" != "${STEP3_USE_T2}" || "${manifest_mask_mode}" != "${STEP3_MASK_MODE}" || "${manifest_use_mask:-0}" != "${STEP3_USE_MASK}" || "${manifest_use_affine:-1}" != "${STEP3_USE_AFFINE}" ]]; then
    reset_step3_outputs
  elif [[ "${STEP3_USE_T2}" == "1" && "${manifest_mni_t2}" != "${MNI_T2}" ]]; then
    reset_step3_outputs
  elif [[ "${STEP3_USE_MASK}" == "1" && "${manifest_mask_path}" != "${MNI_SUBCORTICAL_MASK}" ]]; then
    reset_step3_outputs
  fi
fi

# 如果当前 step 的主要结果都已存在，则直接跳过。
if step3_outputs_ready; then
  log "[phase1_anat] Step3 already done for ${SUBJECT_ID}"
  exit 0
fi

# 先准备 MNI2009b 的脑模板，用作固定模板侧的输入。
if [[ ! -f "${MNI_BRAIN}" ]]; then
  fslmaths "${MNI_T1}" -mas "${MNI_BRAINMASK}" "${MNI_BRAIN}"
fi

if [[ "${STEP3_USE_T2}" == "1" && ! -f "${MNI_T2_BRAIN}" ]]; then
  fslmaths "${MNI_T2}" -mas "${MNI_BRAINMASK}" "${MNI_T2_BRAIN}"
fi

if [[ "${STEP3_USE_MASK}" == "1" && ! -f "${MNI_SUBCORTICAL_MASK_NATIVE}" ]]; then
  fslmaths "${MNI_SUBCORTICAL_MASK}" -bin -mas "${MNI_BRAINMASK}" "${MNI_SUBCORTICAL_MASK_NATIVE}"
fi

if [[ "${STEP3_USE_MASK}" == "1" && ! -f "${NATIVE_SUBCORTICAL_MASK}" ]]; then
  fslmaths "${APARC_ASEG}" -thr 9.5 -uthr 13.5 -bin "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_lh_bg.nii.gz"
  fslmaths "${APARC_ASEG}" -thr 15.5 -uthr 16.5 -bin "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_brainstem.nii.gz"
  fslmaths "${APARC_ASEG}" -thr 25.5 -uthr 28.5 -bin "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_lh_extra.nii.gz"
  fslmaths "${APARC_ASEG}" -thr 48.5 -uthr 52.5 -bin "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_rh_bg.nii.gz"
  fslmaths "${APARC_ASEG}" -thr 57.5 -uthr 60.5 -bin "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_rh_extra.nii.gz"
  fslmaths "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_lh_bg.nii.gz" \
    -add "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_brainstem.nii.gz" \
    -add "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_lh_extra.nii.gz" \
    -add "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_rh_bg.nii.gz" \
    -add "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_rh_extra.nii.gz" \
    -bin -dilM -dilM "${NATIVE_SUBCORTICAL_MASK}"
  rm -f \
    "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_lh_bg.nii.gz" \
    "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_brainstem.nii.gz" \
    "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_lh_extra.nii.gz" \
    "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_rh_bg.nii.gz" \
    "${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask_rh_extra.nii.gz"
fi

# 组装 DISTAL 的 6 个深部核团标签图，后续将它整体逆变换回个体 native space。
if [[ ! -f "${DISTAL_MNI}" || ! -f "${DISTAL_LABELS}" ]]; then
  "${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step3/create_label_atlas.py" \
    --atlas-dir "${DISTAL_ATLAS_DIR}" \
    --roi-list "${CONFIG_DIR}/distal_gpe_gpi_stn_6.tsv" \
    --output-nii "${DISTAL_MNI}" \
    --output-tsv "${DISTAL_LABELS}"
fi

# 组装双侧黑质标签图，后续与 DISTAL 一起逆变换回 native space。
if [[ ! -f "${SN_MNI}" || ! -f "${SN_LABELS}" ]]; then
  "${PYTHON_BIN}" "${UTILS_DIR}/phase1_anat/step3/create_label_atlas.py" \
    --atlas-dir "${SN_ATLAS_DIR}" \
    --roi-list "${CONFIG_DIR}/sn_2.tsv" \
    --output-nii "${SN_MNI}" \
    --output-tsv "${SN_LABELS}"
fi

# 用锁死参数的 SyN 把 MNI2009b 配准到个体原生 T1，优先守住深部核团区域。
if ! resolve_step3_transform_outputs; then
  if [[ "${STEP3_USE_LEADDBS_NATIVE}" == "1" ]]; then
    # 原生 Lead-DBS 的 ANTs 正向定义是 native->MNI；这里把它回写成现有 step5/step6
    # 一直在消费的 mni->native contract，因此下游不需要改 atlas 逆变换逻辑。
    run_leaddbs_native_registration
  else
    MASK_ARGS=()
    AFFINE_STAGE_ARGS=()
    if [[ "${STEP3_USE_MASK}" == "1" ]]; then
      # ANTs 的 mask 按 fixed,moving 顺序传入；这里 fixed 是 native T1/T2，moving 是 MNI 模板侧。
      MASK_ARGS=(--masks "[${NATIVE_SUBCORTICAL_MASK},${MNI_SUBCORTICAL_MASK_NATIVE}]")
    fi
    if [[ "${STEP3_USE_AFFINE}" == "1" ]]; then
      if [[ "${STEP3_USE_T2}" == "1" ]]; then
        AFFINE_STAGE_ARGS=(
          --transform Affine[0.1]
          --metric "MI[${T1_BRAIN},${MNI_BRAIN},1,32,Regular,0.25]"
          --metric "MI[${T2_BRAIN},${MNI_T2_BRAIN},1,32,Regular,0.25]"
          --convergence "[500x250x100,1e-6,10]"
          --shrink-factors 8x4x2
          --smoothing-sigmas 3x2x1vox
        )
      else
        AFFINE_STAGE_ARGS=(
          --transform Affine[0.1]
          --metric "MI[${T1_BRAIN},${MNI_BRAIN},1,32,Regular,0.25]"
          --convergence "[500x250x100,1e-6,10]"
          --shrink-factors 8x4x2
          --smoothing-sigmas 3x2x1vox
        )
      fi
    fi
    if [[ "${STEP3_USE_T2}" == "1" ]]; then
      antsRegistration \
        --dimensionality 3 \
        --float 0 \
        --output "[${REG_PREFIX},${REG_PREFIX}1Warp.nii.gz,${REG_PREFIX}1InverseWarp.nii.gz]" \
        --interpolation Linear \
        --use-histogram-matching 0 \
        --winsorize-image-intensities "[0.005,0.995]" \
        "${MASK_ARGS[@]}" \
        --transform Rigid[0.1] \
        --metric "MI[${T1_BRAIN},${MNI_BRAIN},1,32,Regular,0.25]" \
        --metric "MI[${T2_BRAIN},${MNI_T2_BRAIN},1,32,Regular,0.25]" \
        --convergence "[1000x500x250x100,1e-6,10]" \
        --shrink-factors 8x4x2x1 \
        --smoothing-sigmas 3x2x1x0vox \
        "${AFFINE_STAGE_ARGS[@]}" \
        --transform SyN[0.1,3,0] \
        --metric "CC[${T1_BRAIN},${MNI_BRAIN},1,4]" \
        --metric "CC[${T2_BRAIN},${MNI_T2_BRAIN},1,4]" \
        --convergence "[100x70x50x20,1e-6,10]" \
        --shrink-factors 8x4x2x1 \
        --smoothing-sigmas 3x2x1x0vox >"${PHASE1_ANAT_STEP3_DIR}/ants_syn.log" 2>&1
    else
      antsRegistration \
        --dimensionality 3 \
        --float 0 \
        --output "[${REG_PREFIX},${REG_PREFIX}1Warp.nii.gz,${REG_PREFIX}1InverseWarp.nii.gz]" \
        --interpolation Linear \
        --use-histogram-matching 0 \
        --winsorize-image-intensities "[0.005,0.995]" \
        "${MASK_ARGS[@]}" \
        --transform Rigid[0.1] \
        --metric "MI[${T1_BRAIN},${MNI_BRAIN},1,32,Regular,0.25]" \
        --convergence "[1000x500x250x100,1e-6,10]" \
        --shrink-factors 8x4x2x1 \
        --smoothing-sigmas 3x2x1x0vox \
        "${AFFINE_STAGE_ARGS[@]}" \
        --transform SyN[0.1,3,0] \
        --metric "CC[${T1_BRAIN},${MNI_BRAIN},1,4]" \
        --convergence "[100x70x50x20,1e-6,10]" \
        --shrink-factors 8x4x2x1 \
        --smoothing-sigmas 3x2x1x0vox >"${PHASE1_ANAT_STEP3_DIR}/ants_syn.log" 2>&1
    fi
  fi
fi

resolve_step3_transform_outputs || die "Step3 registration finished but expected transforms are missing under ${REG_PREFIX}"
if [[ -z "${STEP3_FORWARD_AFFINE}" ]]; then
  log "[phase1_anat] Step3 detected composite warp-only output for ${SUBJECT_ID}; downstream steps will reuse the composite warp without a separate affine"
fi

# 写出当前 step 的输出清单。
cat > "${STEP3_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
registration_engine	${STEP3_REGISTRATION_ENGINE}
registration_mode	${STEP3_REGISTRATION_MODE}
registration_use_t2	${STEP3_USE_T2}
registration_reason	${STEP3_REGISTRATION_REASON}
registration_use_affine	${STEP3_USE_AFFINE}
affine_reason	${STEP3_AFFINE_REASON}
registration_use_mask	${STEP3_USE_MASK}
registration_mask_mode	${STEP3_MASK_MODE}
mask_reason	${STEP3_MASK_REASON}
locked_preset	${PHASE1_LEADDBS_PRESET}
fixed_image	${T1_BRAIN}
fixed_t2_image	$( [[ "${STEP3_USE_T2}" == "1" ]] && echo "${T2_BRAIN}" || echo "" )
moving_image	${MNI_BRAIN}
mni_t2	$( [[ "${STEP3_USE_T2}" == "1" ]] && echo "${MNI_T2}" || echo "" )
mni_t2_brain	$( [[ "${STEP3_USE_T2}" == "1" ]] && echo "${MNI_T2_BRAIN}" || echo "" )
mni_subcortical_mask	$( [[ "${STEP3_USE_MASK}" == "1" ]] && echo "${MNI_SUBCORTICAL_MASK}" || echo "" )
mni_subcortical_mask_prepared	$( [[ "${STEP3_USE_MASK}" == "1" ]] && echo "${MNI_SUBCORTICAL_MASK_NATIVE}" || echo "" )
native_subcortical_mask	$( [[ "${STEP3_USE_MASK}" == "1" ]] && echo "${NATIVE_SUBCORTICAL_MASK}" || echo "" )
distal_mni	${DISTAL_MNI}
distal_labels	${DISTAL_LABELS}
sn_mni	${SN_MNI}
sn_labels	${SN_LABELS}
transform_layout	${STEP3_TRANSFORM_LAYOUT}
forward_affine	${STEP3_FORWARD_AFFINE}
forward_warp	${STEP3_FORWARD_WARP}
inverse_warp	${STEP3_INVERSE_WARP}
leaddbs_native_dir	$( [[ "${STEP3_USE_LEADDBS_NATIVE}" == "1" ]] && echo "${LEADDBS_NATIVE_DIR}" || echo "" )
leaddbs_native_log	$( [[ "${STEP3_USE_LEADDBS_NATIVE}" == "1" ]] && echo "${LEADDBS_NATIVE_LOG}" || echo "" )
EOF

# 把当前 step 的关键模板结果链接到 stepview，便于快速核对。
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 1 "mni2009b_brain" "${MNI_BRAIN}"
if [[ "${STEP3_USE_T2}" == "1" ]]; then
  link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 2 "mni2009b_t2_brain" "${MNI_T2_BRAIN}"
  link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 3 "t2_coreg_t1_brain" "${T2_BRAIN}"
  if [[ "${STEP3_USE_MASK}" == "1" ]]; then
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 4 "mni_subcortical_mask" "${MNI_SUBCORTICAL_MASK_NATIVE}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 5 "native_subcortical_mask" "${NATIVE_SUBCORTICAL_MASK}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 6 "distal_mni" "${DISTAL_MNI}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 7 "sn_mni" "${SN_MNI}"
  else
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 4 "distal_mni" "${DISTAL_MNI}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 5 "sn_mni" "${SN_MNI}"
  fi
else
  if [[ "${STEP3_USE_MASK}" == "1" ]]; then
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 2 "mni_subcortical_mask" "${MNI_SUBCORTICAL_MASK_NATIVE}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 3 "native_subcortical_mask" "${NATIVE_SUBCORTICAL_MASK}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 4 "distal_mni" "${DISTAL_MNI}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 5 "sn_mni" "${SN_MNI}"
  else
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 2 "distal_mni" "${DISTAL_MNI}"
    link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 3 3 "sn_mni" "${SN_MNI}"
  fi
fi
