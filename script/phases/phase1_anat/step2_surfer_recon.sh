#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset、surfer 类型和 subject 的配置。
load_config
# 加载 FreeSurfer / FastSurfer 等工具环境。
setup_tools_env

# 检查当前 step 依赖的核心命令。
require_cmd mri_convert
require_cmd mri_vol2vol
require_cmd mri_binarize
if [[ "${SURFER_TYPE}" == "free" ]]; then
  require_cmd recon-all
  require_cmd mri_aparc2aseg
else
  [[ -f "${FASTSURFER_HOME}/run_fastsurfer.sh" ]] || die "Missing FastSurfer entrypoint: ${FASTSURFER_HOME}/run_fastsurfer.sh"
fi

# 定义当前 step 的核心输入输出。
STEP2_MANIFEST="${PHASE1_ANAT_STEP2_DIR}/manifest.tsv"
BIDS_T1_INPUT="${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.nii.gz"
T1_NATIVE_INPUT="${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz"
T1_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz"
T1_MASK="${PHASE1_ANAT_STEP1_DIR}/t1_brain_mask.nii.gz"
T1_FS_XMASK="${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_xmask.nii.gz"
T1_FS_BRAIN="${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_brain.nii.gz"
SURFER_SUBJECTS_DIR="${PHASE1_ANAT_STEP2_DIR}/surfer_subjects"
SURFER_SUBJECT_DIR="${SURFER_SUBJECTS_DIR}/${SUBJECT_ID}"
APARC_ASEG="${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz"
SURFER_DONE="${PHASE1_ANAT_STEP2_DIR}/surfer.done"
if [[ "${SURFER_TYPE}" == "free" ]]; then
  SURFER_ENGINE_LOG="${PHASE1_ANAT_STEP2_DIR}/recon-all.log"
else
  SURFER_ENGINE_LOG="${PHASE1_ANAT_STEP2_DIR}/fastsurfer.log"
fi
FS_DONE="${SURFER_SUBJECT_DIR}/scripts/recon-all.done"
FS_ERROR="${SURFER_SUBJECT_DIR}/scripts/recon-all.error"
SURFER_LH_WHITE="${SURFER_SUBJECT_DIR}/surf/lh.white"
SURFER_RH_WHITE="${SURFER_SUBJECT_DIR}/surf/rh.white"
SURFER_BRAINMASK="${SURFER_SUBJECT_DIR}/mri/brainmask.mgz"
SURFER_BRAINMASK_AUTO="${SURFER_SUBJECT_DIR}/mri/brainmask.auto.mgz"
SURFER_ORIG="${SURFER_SUBJECT_DIR}/mri/orig.mgz"
SURFER_NU="${SURFER_SUBJECT_DIR}/mri/nu.mgz"
SURFER_T1="${SURFER_SUBJECT_DIR}/mri/T1.mgz"
SURFER_APARC_ASEG_MGZ="${SURFER_SUBJECT_DIR}/mri/aparc+aseg.mgz"
FASTSURFER_DEEPSEG_MGZ="${SURFER_SUBJECT_DIR}/mri/aparc.DKTatlas+aseg.deep.mgz"
FASTSURFER_MAPPED_MGZ="${SURFER_SUBJECT_DIR}/mri/aparc.DKTatlas+aseg.mapped.mgz"
FASTSURFER_ORIG_NU="${SURFER_SUBJECT_DIR}/mri/orig_nu.mgz"
FASTSURFER_MASK="${SURFER_SUBJECT_DIR}/mri/mask.mgz"
FS_EXPERT_OPTS="${PHASE1_ANAT_STEP2_DIR}/recon-all.expert.opts"
PHASE0_STEP1_MANIFEST="${PHASE0_INIT_STEP1_DIR}/manifest.tsv"

# 把 FreeSurfer/FastSurfer 的 SUBJECTS_DIR 导出给后续命令使用。
export SUBJECTS_DIR="${SURFER_SUBJECTS_DIR}"
mkdir -p "${SURFER_SUBJECTS_DIR}"

surfer_surfaces_ready() {
  [[ -f "${SURFER_LH_WHITE}" && -f "${SURFER_RH_WHITE}" ]]
}

surfer_pial_surfaces_ready() {
  [[ -f "${SURFER_SUBJECT_DIR}/surf/lh.pial" && -f "${SURFER_SUBJECT_DIR}/surf/rh.pial" ]]
}

fastsurfer_surfaces_ready() {
  surfer_surfaces_ready || return 1
  surfer_pial_surfaces_ready || return 1
}

surfer_core_volumes_ready() {
  [[ -f "${SURFER_ORIG}" && -f "${SURFER_NU}" && -f "${SURFER_T1}" && -f "${SURFER_BRAINMASK}" ]]
}

surfer_aparc_mgz_ready() {
  [[ -f "${SURFER_APARC_ASEG_MGZ}" ]]
}

freesurfer_engine_outputs_ready() {
  [[ "${SURFER_TYPE}" == "free" ]] || return 1
  surfer_surfaces_ready || return 1
  surfer_core_volumes_ready || return 1
  surfer_aparc_mgz_ready || return 1
}

fastsurfer_segmentation_ready() {
  [[ -f "${SURFER_ORIG}" && -f "${FASTSURFER_ORIG_NU}" && -f "${FASTSURFER_MASK}" && -f "${FASTSURFER_DEEPSEG_MGZ}" ]]
}

fastsurfer_mapped_aparc_ready() {
  [[ -f "${FASTSURFER_MAPPED_MGZ}" ]]
}

ensure_fastsurfer_surface_inputs() {
  mkdir -p "${SURFER_SUBJECT_DIR}/mri"
  if [[ -f "${FASTSURFER_ORIG_NU}" && ! -f "${SURFER_NU}" ]]; then
    cp -f "${FASTSURFER_ORIG_NU}" "${SURFER_NU}"
  fi
  if [[ -f "${FASTSURFER_MASK}" && ! -f "${SURFER_BRAINMASK}" ]]; then
    cp -f "${FASTSURFER_MASK}" "${SURFER_BRAINMASK}"
    cp -f "${FASTSURFER_MASK}" "${SURFER_BRAINMASK_AUTO}" || true
  fi
}

ensure_fastsurfer_aparc_aseg() {
  if [[ ! -f "${SURFER_APARC_ASEG_MGZ}" && -f "${FASTSURFER_MAPPED_MGZ}" ]]; then
    cp -f "${FASTSURFER_MAPPED_MGZ}" "${SURFER_APARC_ASEG_MGZ}"
  fi
}

fastsurfer_recoverable_segstats_failure() {
  [[ -f "${SURFER_ENGINE_LOG}" ]] || return 1
  grep -q "TypeError: The seg object is not a numpy.ndarray of <class 'numpy.integer'>" "${SURFER_ENGINE_LOG}" || return 1
  fastsurfer_surfaces_ready || return 1
  surfer_core_volumes_ready || return 1
  fastsurfer_mapped_aparc_ready || return 1
}

fastsurfer_engine_outputs_ready() {
  fastsurfer_surfaces_ready || return 1
  surfer_core_volumes_ready || return 1
  fastsurfer_mapped_aparc_ready || return 1
}

freesurfer_uses_v8_defaults() {
  [[ "${SURFER_TYPE}" == "free" ]] || return 1
  [[ "${PHASE1_FREESURFER_V8_GUARD:-0}" == "1" ]] || return 1
  if [[ -f "${SURFER_SUBJECT_DIR}/mri/synthstrip.mgz" || -f "${SURFER_SUBJECT_DIR}/mri/synthseg.rca.mgz" ]]; then
    return 0
  fi
  [[ -f "${SURFER_ENGINE_LOG}" ]] || return 1
  grep -q -- "-synthstrip" "${SURFER_ENGINE_LOG}" || return 1
  grep -q -- "-synthseg" "${SURFER_ENGINE_LOG}" || return 1
  grep -q -- "-synthmorph" "${SURFER_ENGINE_LOG}" || return 1
}

aparc_native_ready() {
  [[ -f "${APARC_ASEG}" ]] || return 1
  "${PYTHON_BIN}" - "${T1_NATIVE_INPUT}" "${APARC_ASEG}" <<'PY'
import sys
import nibabel as nib
import numpy as np

t1 = nib.load(sys.argv[1])
aparc = nib.load(sys.argv[2])
same_shape = t1.shape == aparc.shape
same_affine = np.allclose(t1.affine, aparc.affine)
raise SystemExit(0 if same_shape and same_affine else 1)
PY
}

ensure_freesurfer_brainmask() {
  local tmp_brain="${PHASE1_ANAT_STEP2_DIR}/t1_freesurfer_brain_input.mgz"
  local source_brain="${T1_FS_BRAIN}"
  [[ -f "${source_brain}" ]] || source_brain="${T1_BRAIN}"
  [[ -f "${source_brain}" ]] || die "Missing FreeSurfer brain volume: ${source_brain}"
  [[ -f "${SURFER_ORIG}" ]] || die "Cannot build FreeSurfer brainmask before orig.mgz exists"

  mkdir -p "${SURFER_SUBJECT_DIR}/mri"
  mri_convert "${source_brain}" "${tmp_brain}" >"${PHASE1_ANAT_STEP2_DIR}/mri_convert_brainmask.log" 2>&1
  mri_vol2vol \
    --mov "${tmp_brain}" \
    --targ "${SURFER_ORIG}" \
    --regheader \
    --interp trilinear \
    --o "${SURFER_BRAINMASK_AUTO}" >"${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_brainmask.log" 2>&1
  cp -f "${SURFER_BRAINMASK_AUTO}" "${SURFER_BRAINMASK}"
}

write_dataset_specific_expert_opts() {
  [[ "${SURFER_TYPE}" == "free" ]] || {
    rm -f "${FS_EXPERT_OPTS}"
    return 0
  }
  if [[ -n "${PHASE1_FREESURFER_CORTEX_LABEL_ARGS:-}" ]]; then
    printf 'CortexLabel %s\n' "${PHASE1_FREESURFER_CORTEX_LABEL_ARGS}" >"${FS_EXPERT_OPTS}"
  else
    rm -f "${FS_EXPERT_OPTS}"
  fi
}

step_manifest_value() {
  local manifest_path="$1"
  local manifest_key="$2"
  [[ -f "$manifest_path" ]] || return 0
  awk -F '\t' -v target="$manifest_key" '$1 == target { print $2; exit }' "$manifest_path"
}

step2_requires_config_refresh() {
  local manifest_hires=""
  local manifest_fastsurfer_vox_size=""
  local manifest_t1_resample_voxel_size=""
  local current_t1_resample_voxel_size="${INIT_T1_RESAMPLE_VOXEL_SIZE:-1}"

  if [[ ! -f "${STEP2_MANIFEST}" ]]; then
    if [[ -d "${SURFER_SUBJECT_DIR}" ]] && { [[ "${PHASE1_SURFER_HIRES:-0}" == "1" ]] || [[ "${INIT_T1_RESAMPLE_ENABLE:-0}" == "1" ]] || { [[ "${SURFER_TYPE}" == "fast" && "${PHASE1_FASTSURFER_VOX_SIZE:-min}" != "min" ]]; }; }; then
      return 0
    fi
    return 1
  fi

  manifest_hires="$(step_manifest_value "${STEP2_MANIFEST}" "surfer_hires")"
  if [[ "${PHASE1_SURFER_HIRES:-0}" == "1" && "${manifest_hires}" != "1" ]]; then
    return 0
  fi

  if [[ "${SURFER_TYPE}" == "fast" && "${PHASE1_FASTSURFER_VOX_SIZE:-min}" != "min" ]]; then
    manifest_fastsurfer_vox_size="$(step_manifest_value "${STEP2_MANIFEST}" "fastsurfer_vox_size")"
    if [[ "${manifest_fastsurfer_vox_size}" != "${PHASE1_FASTSURFER_VOX_SIZE:-min}" ]]; then
      return 0
    fi
  fi

  if [[ "${INIT_T1_RESAMPLE_ENABLE:-0}" == "1" ]]; then
    manifest_t1_resample_voxel_size="$(step_manifest_value "${STEP2_MANIFEST}" "t1_resample_voxel_size_mm")"
    if [[ "${manifest_t1_resample_voxel_size}" != "${current_t1_resample_voxel_size}" ]]; then
      return 0
    fi
  fi

  return 1
}

reset_surfer_subject() {
  local reason="$1"
  log "[phase1_anat] Step2 resetting ${SURFER_LABEL} subject for ${SUBJECT_ID}: ${reason}"
  rm -rf "${SURFER_SUBJECT_DIR}"
  rm -f "${APARC_ASEG}" \
    "${SURFER_DONE}" \
    "${SURFER_ENGINE_LOG}" \
    "${STEP2_MANIFEST}" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_aparc2aseg.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_aparc_native.log" \
    "${PHASE1_ANAT_STEP2_DIR}/recon-all-init.log"
}

write_surfer_done() {
  cat > "${SURFER_DONE}" <<EOF
surfer_type	${SURFER_TYPE}
surfer_label	${SURFER_LABEL}
subject_id	${SUBJECT_ID}
subject_dir	${SURFER_SUBJECT_DIR}
EOF
}

surfer_hires_args() {
  if [[ "${PHASE1_SURFER_HIRES:-0}" == "1" ]]; then
    printf '%s\n' "-hires"
  fi
}

run_freesurfer() {
  local fs_xmask="${T1_FS_XMASK}"
  local recon_args=()
  local hires_args=()
  [[ -f "${fs_xmask}" ]] || fs_xmask="${T1_MASK}"
  mapfile -t hires_args < <(surfer_hires_args)
  recon_args+=("${hires_args[@]}")
  if [[ -f "${FS_EXPERT_OPTS}" ]]; then
    recon_args+=(-expert "${FS_EXPERT_OPTS}" -xopts-overwrite)
  fi
  if [[ "${PHASE1_FREESURFER_NO_V8:-0}" == "1" ]]; then
    # Some dataset configs require the classic external-skullstrip path because
    # FreeSurfer 8 v8 defaults inject synthstrip/synthseg/synthmorph steps.
    recon_args+=(-no-v8)
  fi
  if [[ -f "${SURFER_SUBJECT_DIR}/mri/orig/001.mgz" ]]; then
    recon-all -s "${SUBJECT_ID}" -all -noskullstrip -xmask "${fs_xmask}" -openmp "${NTHREADS}" "${recon_args[@]}" >"${SURFER_ENGINE_LOG}" 2>&1
  else
    recon-all -i "${T1_NATIVE_INPUT}" -s "${SUBJECT_ID}" -all -noskullstrip -xmask "${fs_xmask}" -openmp "${NTHREADS}" "${recon_args[@]}" >"${SURFER_ENGINE_LOG}" 2>&1
  fi
}

run_fastsurfer() {
  local fastsurfer_t1="${BIDS_T1_INPUT}"
  [[ -f "${fastsurfer_t1}" ]] || fastsurfer_t1="${T1_NATIVE_INPUT}"
  [[ -f "${fastsurfer_t1}" ]] || die "Missing FastSurfer T1 input: ${BIDS_T1_INPUT}"
  local fastsurfer_label_cortex_args="${PHASE1_FASTSURFER_LABEL_CORTEX_ARGS:-}"
  local fastsurfer_vox_size="${PHASE1_FASTSURFER_VOX_SIZE:-min}"
  local fastsurfer_args=()
  export MPLCONFIGDIR="${MPLCONFIGDIR:-/tmp/mpl_fastsurfer}"
  mkdir -p "${MPLCONFIGDIR}"
  export CNS_FASTSURFER_LABEL_CORTEX_ARGS="${fastsurfer_label_cortex_args}"
  export CNS_FASTSURFER_FORCE_HIRES="${PHASE1_SURFER_HIRES:-0}"

  if fastsurfer_segmentation_ready && ! fastsurfer_engine_outputs_ready; then
    ensure_fastsurfer_surface_inputs
    fastsurfer_args=(
      --fs_license "${FS_LICENSE}" \
      --sid "${SUBJECT_ID}" \
      --sd "${SURFER_SUBJECTS_DIR}" \
      --threads "${NTHREADS}" \
      --ignore_fs_version \
      --surf_only \
      --edits \
      --py "${FASTSURFER_PYTHON}"
    )
    if [[ "$fastsurfer_vox_size" != "min" ]]; then
      fastsurfer_args+=(--vox_size "$fastsurfer_vox_size")
    fi
    bash "${FASTSURFER_HOME}/run_fastsurfer.sh" "${fastsurfer_args[@]}" >"${SURFER_ENGINE_LOG}" 2>&1
  else
    fastsurfer_args=(
      --fs_license "${FS_LICENSE}" \
      --sid "${SUBJECT_ID}" \
      --sd "${SURFER_SUBJECTS_DIR}" \
      --t1 "${fastsurfer_t1}" \
      --threads "${NTHREADS}" \
      --device "${FASTSURFER_DEVICE:-cpu}" \
      --viewagg_device "${FASTSURFER_VIEWAGG_DEVICE:-cpu}" \
      --ignore_fs_version \
      --parallel \
      --py "${FASTSURFER_PYTHON}"
    )
    if [[ "$fastsurfer_vox_size" != "min" ]]; then
      fastsurfer_args+=(--vox_size "$fastsurfer_vox_size")
    fi
    bash "${FASTSURFER_HOME}/run_fastsurfer.sh" "${fastsurfer_args[@]}" >"${SURFER_ENGINE_LOG}" 2>&1
  fi
}

# 输出当前 step 的开始日志。
log "[phase1_anat] Step2 ${SURFER_LABEL} recon for ${SUBJECT_ID}"

# 在进入 recon-all 前先写出 dataset 专属 expert 选项。
write_dataset_specific_expert_opts

if step2_requires_config_refresh; then
  reset_surfer_subject "config changed"
fi

# 如果当前 step 的主要结果都已存在且 aparc+aseg 已处于 T1 native space，则直接跳过。
# 这里要兼容旧版 FreeSurfer 结果：历史产物可能还没有新的 surfer.done，但关键输出已经齐全。
if [[ -f "${STEP2_MANIFEST}" ]] && surfer_surfaces_ready && surfer_core_volumes_ready && aparc_native_ready && ! freesurfer_uses_v8_defaults; then
  [[ -f "${SURFER_DONE}" ]] || write_surfer_done
  log "[phase1_anat] Step2 already done for ${SUBJECT_ID}"
  exit 0
fi

# 兼容历史 FastSurfer 结果：如果引擎级产物已经齐全，只差外层导出，不要重复跑 FastSurfer。
if [[ "${SURFER_TYPE}" == "fast" ]] && fastsurfer_engine_outputs_ready; then
  ensure_fastsurfer_surface_inputs
  ensure_fastsurfer_aparc_aseg
fi

# 兼容历史 FreeSurfer 结果：如果 recon-all 已经完整结束、只是在 step2 外层收尾阶段中断，
# 则直接复用现有 subject 目录继续导出，不要再重跑 recon-all。
if freesurfer_engine_outputs_ready; then
  [[ -f "${SURFER_DONE}" ]] || write_surfer_done
fi

# 如果上次 FreeSurfer 中断留下了死锁文件，则在确认进程已不存在后清理锁文件。
if [[ "${SURFER_TYPE}" == "free" && -f "${SURFER_SUBJECT_DIR}/scripts/IsRunning.lh+rh" && ! -f "${FS_DONE}" ]]; then
  fs_pid="$(awk '/^PROCESSID/ {print $2}' "${SURFER_SUBJECT_DIR}/scripts/IsRunning.lh+rh" | head -n 1 || true)"
  if [[ -z "${fs_pid}" ]] || ! kill -0 "${fs_pid}" 2>/dev/null; then
    rm -f "${SURFER_SUBJECT_DIR}/scripts/IsRunning.lh+rh"
  fi
fi

# 如果上次 FreeSurfer 已经失败，或者留下了假的 done 但关键中间结果并不完整，则清空坏掉的 subject 后重新开始。
if [[ "${SURFER_TYPE}" == "free" ]] && { [[ -f "${FS_ERROR}" ]] || [[ -f "${FS_DONE}" ]] || [[ -f "${SURFER_DONE}" ]] || freesurfer_uses_v8_defaults; } && { ! surfer_surfaces_ready || ! surfer_core_volumes_ready || freesurfer_uses_v8_defaults; }; then
  log "[phase1_anat] Step2 resetting incomplete ${SURFER_LABEL} subject for ${SUBJECT_ID}"
  rm -rf "${SURFER_SUBJECT_DIR}"
  rm -f "${APARC_ASEG}" \
    "${SURFER_DONE}" \
    "${SURFER_ENGINE_LOG}" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_aparc2aseg.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_convert_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_brainmask.log" \
    "${PHASE1_ANAT_STEP2_DIR}/recon-all-init.log"
fi

# FastSurfer 如果落下了假的 done 标记，但引擎级产物并未真正齐全，先去掉完成标记，避免后续误判。
if [[ "${SURFER_TYPE}" == "fast" && -f "${SURFER_DONE}" ]] && ! fastsurfer_engine_outputs_ready; then
  rm -f "${SURFER_DONE}"
fi

# FastSurfer 如果已经留下了完整 segmentation 但表面还没生成，则保留分割结果，转入 surf_only 续跑。
if [[ "${SURFER_TYPE}" == "fast" ]] && [[ -d "${SURFER_SUBJECT_DIR}" ]] && ! fastsurfer_engine_outputs_ready && fastsurfer_segmentation_ready; then
  ensure_fastsurfer_surface_inputs
fi

# FastSurfer 如果是半残缺目录且 segmentation 也不完整，则直接清空后从头来，避免反复踩 existing subject directory。
if [[ "${SURFER_TYPE}" == "fast" ]] && [[ -d "${SURFER_SUBJECT_DIR}" ]] && ! fastsurfer_engine_outputs_ready && ! fastsurfer_segmentation_ready; then
  log "[phase1_anat] Step2 resetting incomplete FastSurfer subject for ${SUBJECT_ID}"
  rm -rf "${SURFER_SUBJECT_DIR}"
  rm -f "${APARC_ASEG}" "${SURFER_DONE}" "${SURFER_ENGINE_LOG}"
fi

# 如果上次留下了假的 done 标记但表面没有真正生成，则清掉 done 并继续修复性续跑。
if [[ -f "${FS_DONE}" ]] && { { [[ "${SURFER_TYPE}" == "fast" ]] && ! fastsurfer_engine_outputs_ready; } || { [[ "${SURFER_TYPE}" != "fast" ]] && ! surfer_surfaces_ready; }; }; then
  rm -f "${FS_DONE}" "${SURFER_DONE}"
fi

# 用选定的 surfer 引擎执行表面重建。
if [[ ! -f "${SURFER_DONE}" ]] || ! surfer_surfaces_ready; then
  if [[ "${SURFER_TYPE}" == "fast" ]] && fastsurfer_engine_outputs_ready; then
    :
  else
    set +e
    if [[ "${SURFER_TYPE}" == "free" ]]; then
      run_freesurfer
    else
      run_fastsurfer
    fi
    recon_status=$?
    set -e

    # 如果第一次失败是因为缺 brainmask，则自动补脑掩膜并重新续跑一次。
    if (( recon_status != 0 )) && [[ "${SURFER_TYPE}" == "free" ]]; then
      if [[ -f "${SURFER_ORIG}" ]] && grep -q "could not open mask volume brainmask.mgz" "${SURFER_ENGINE_LOG}"; then
        log "[phase1_anat] Step2 detected missing FreeSurfer brainmask, repairing and resuming"
        ensure_freesurfer_brainmask
        rm -f "${FS_DONE}" "${SURFER_DONE}"
        set +e
        run_freesurfer
        recon_status=$?
        set -e
      fi
    fi

    if (( recon_status != 0 )) && [[ "${SURFER_TYPE}" == "fast" ]] && fastsurfer_recoverable_segstats_failure; then
      log "[phase1_anat] Step2 detected recoverable FastSurfer segstats failure for ${SUBJECT_ID}, reusing completed surfaces and mapped aparc+aseg"
      ensure_fastsurfer_surface_inputs
      ensure_fastsurfer_aparc_aseg
      recon_status=0
    fi

    (( recon_status == 0 )) || die "${SURFER_LABEL} recon failed: ${PHASE1_ANAT_STEP2_DIR}"
  fi
fi

# 在导出 aparc+aseg 前再次确认关键表面已经生成。
if [[ "${SURFER_TYPE}" == "fast" ]]; then
  fastsurfer_surfaces_ready || die "${SURFER_LABEL} surfaces missing after recon: ${SURFER_SUBJECT_DIR}/surf"
else
  surfer_surfaces_ready || die "${SURFER_LABEL} surfaces missing after recon: ${SURFER_SUBJECT_DIR}/surf"
fi
surfer_core_volumes_ready || die "${SURFER_LABEL} core volumes missing after recon: ${SURFER_SUBJECT_DIR}/mri"
if [[ "${SURFER_TYPE}" == "fast" ]]; then
  ensure_fastsurfer_aparc_aseg
fi

# 导出体素版 aparc+aseg，并强制回到原始 T1 native space。
if [[ ! -f "${SURFER_APARC_ASEG_MGZ}" && "${SURFER_TYPE}" == "free" ]]; then
  mri_aparc2aseg --s "${SUBJECT_ID}" --annot aparc --o "${SURFER_APARC_ASEG_MGZ}" >"${PHASE1_ANAT_STEP2_DIR}/mri_aparc2aseg.log" 2>&1
fi

[[ -f "${SURFER_APARC_ASEG_MGZ}" ]] || die "Missing aparc+aseg from ${SURFER_LABEL}: ${SURFER_APARC_ASEG_MGZ}"

if ! aparc_native_ready; then
  mri_vol2vol \
    --mov "${SURFER_APARC_ASEG_MGZ}" \
    --targ "${T1_NATIVE_INPUT}" \
    --regheader \
    --interp nearest \
    --o "${APARC_ASEG}" >"${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_aparc_native.log" 2>&1
fi

write_surfer_done

# 写出当前 step 的输出清单。
cat > "${STEP2_MANIFEST}" <<EOF
key	value
subject_id	${SUBJECT_ID}
surfer_type	${SURFER_TYPE}
surfer_label	${SURFER_LABEL}
bids_t1_input	${BIDS_T1_INPUT}
t1_native_input	${T1_NATIVE_INPUT}
t1_brain	${T1_BRAIN}
t1_brain_mask	${T1_MASK}
t1_freesurfer_xmask	${T1_FS_XMASK}
t1_freesurfer_brain	${T1_FS_BRAIN}
surfer_subjects_dir	${SURFER_SUBJECTS_DIR}
surfer_subject_dir	${SURFER_SUBJECT_DIR}
surfer_engine_log	${SURFER_ENGINE_LOG}
recon_all_args	$( [[ "${SURFER_TYPE}" == "free" ]] && echo "-i ${T1_NATIVE_INPUT} -all -noskullstrip -xmask ${T1_FS_XMASK} -openmp ${NTHREADS}$( [[ "${PHASE1_SURFER_HIRES:-0}" == "1" ]] && printf ' -hires' )$( [[ "${PHASE1_FREESURFER_NO_V8:-0}" == "1" ]] && printf ' -no-v8' )" || echo "run_fastsurfer.sh --sid ${SUBJECT_ID} --sd ${SURFER_SUBJECTS_DIR} --t1 ${BIDS_T1_INPUT} --threads ${NTHREADS} --device ${FASTSURFER_DEVICE:-cpu} --viewagg_device ${FASTSURFER_VIEWAGG_DEVICE:-cpu} --vox_size ${PHASE1_FASTSURFER_VOX_SIZE:-min} --ignore_fs_version" )
surfer_hires	${PHASE1_SURFER_HIRES:-0}
fastsurfer_vox_size	${PHASE1_FASTSURFER_VOX_SIZE:-min}
t1_resample_voxel_size_mm	${INIT_T1_RESAMPLE_VOXEL_SIZE:-1}
recon_all_expert_opts	${FS_EXPERT_OPTS}
freesurfer_cortex_label_args	$( [[ "${SURFER_TYPE}" == "free" ]] && echo "${PHASE1_FREESURFER_CORTEX_LABEL_ARGS:-}" || echo "" )
fastsurfer_label_cortex_args	$( [[ "${SURFER_TYPE}" == "fast" ]] && echo "${PHASE1_FASTSURFER_LABEL_CORTEX_ARGS:-}" || echo "" )
brainmask_mgz	${SURFER_BRAINMASK}
aparc_aseg	${APARC_ASEG}
EOF

# 把当前 step 的关键体素结果链接到 stepview，便于直接核对。
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 2 1 "surfer_input_t1" "${T1_NATIVE_INPUT}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 2 2 "surfer_aux_mask" "${T1_FS_XMASK}"
link_phase_product_nifti "${PHASE1_ANAT_STEPVIEW_DIR}" 2 3 "aparc_aseg" "${APARC_ASEG}"
