# CNS Lab MRI Pipeline Details

本层按当前代码真实路径记录目录树、phase 路径和关键文件命名，可直接对照代码复刻。

## Code And Config Entry Points

```text
/data/bryang/project/CNS/pipeline/script/process.sh
/data/bryang/project/CNS/pipeline/script/parallel.sh
/data/bryang/project/CNS/pipeline/script/run/*.sh
/data/bryang/project/CNS/pipeline/script/common.sh
/data/bryang/project/CNS/pipeline/config/pipeline.env
/data/bryang/project/CNS/pipeline/config/datasets/hcp.env
/data/bryang/project/CNS/pipeline/config/datasets/parkinson.env
```

## Dataset Roots

HCP:

```text
RAW_ROOT=/data/bryang/project/CNS/data/HCP/raw
WORKSPACE_ROOT=/data/bryang/project/CNS/data/HCP/workspace
```

Parkinson:

```text
RAW_ROOT=/data/bryang/project/CNS/data/Parkinson/raw
WORKSPACE_ROOT=/data/bryang/project/CNS/data/Parkinson/workspace
```

## Subject Workspace Formula

记号：

```text
SURFER_LABEL=<FreeSurfer|FastSurfer>
SUBJECT_KEY=<001|100610|...>
SUBJECT_ID=sub-<SUBJECT_KEY>
```

subject 根目录：

```text
SUBJECT_WORK_ROOT=/data/bryang/project/CNS/data/<HCP|Parkinson>/workspace/<FreeSurfer|FastSurfer>/<SUBJECT_KEY>
```

标准子树：

```text
${SUBJECT_WORK_ROOT}/bids/${SUBJECT_ID}/anat
${SUBJECT_WORK_ROOT}/bids/${SUBJECT_ID}/func
${SUBJECT_WORK_ROOT}/bids/${SUBJECT_ID}/dwi
${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase0_init
${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase1_anat
${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase2_fmri
${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase3_dwi
${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase4_summary
${SUBJECT_WORK_ROOT}/visualization/phase0_init
${SUBJECT_WORK_ROOT}/visualization/phase1_anat
${SUBJECT_WORK_ROOT}/visualization/phase2_fmri
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi
```

## Visualization Layout

当前真实实现中，所有 visualization 和 stepview 都在 subject 根目录下：

```text
${SUBJECT_WORK_ROOT}/visualization/phase0_init/stepview
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t1
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t2
${SUBJECT_WORK_ROOT}/visualization/phase2_fmri/<trial_name>/motion
${SUBJECT_WORK_ROOT}/visualization/phase2_fmri/<trial_name>/bbr
${SUBJECT_WORK_ROOT}/visualization/phase2_fmri/<trial_name>/stepview
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/registration
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/stepview
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/compare_radial.png
```

兼容逻辑：

- `common.sh` 会把旧的 phase 内 `visualization/` 和 `stepview/` 自动迁到上述位置。
- 旧路径保留为 symlink，因此旧脚本仍可访问，但真实产物根目录以 subject 根下 `visualization/` 为准。

## Phase Root Variables

当前 `common.sh` 中的核心目录变量：

```text
PHASE0_INIT_DIR=${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase0_init
PHASE0_INIT_STEP1_DIR=${PHASE0_INIT_DIR}/step1_bids_standardize

PHASE1_ANAT_DIR=${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase1_anat
PHASE1_ANAT_STEP1_DIR=${PHASE1_ANAT_DIR}/step1_brain_extract
PHASE1_ANAT_STEP2_DIR=${PHASE1_ANAT_DIR}/step2_surfer_recon
PHASE1_ANAT_STEP3_DIR=${PHASE1_ANAT_DIR}/step3_subcortical_syn
PHASE1_ANAT_STEP4_DIR=${PHASE1_ANAT_DIR}/step4_warpdrive_review
PHASE1_ANAT_STEP5_DIR=${PHASE1_ANAT_DIR}/step5_save_inverse_warp
PHASE1_ANAT_STEP6_DIR=${PHASE1_ANAT_DIR}/step6_distal_inverse_fusion
ATLAS_DIR=${PHASE1_ANAT_DIR}/atlas

PHASE2_FMRI_DIR=${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase2_fmri
PHASE3_DWI_DIR=${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase3_dwi

PHASE4_SUMMARY_DIR=${SUBJECT_WORK_ROOT}/derivatives/cns-pipeline/${SUBJECT_ID}/phases/phase4_summary
FINAL_DIR=${PHASE4_SUMMARY_DIR}/final
REPORTS_DIR=${PHASE4_SUMMARY_DIR}/reports
COMPARE_DIR=${PHASE4_SUMMARY_DIR}/comparison
```

## Logs

并行日志：

```text
/data/bryang/project/CNS/pipeline/logs/parallel/<dataset>/<FreeSurfer|FastSurfer>/<subject>.log
```

issues 日志：

```text
/data/bryang/project/CNS/pipeline/issues/log/
```

## Dataset-Relevant Config Keys

当前和数据集最相关的关键参数：

```text
DATASET_IMPORT_MODE
INIT_T1_RESAMPLE_ENABLE
INIT_T1_RESAMPLE_VOXEL_SIZE
INIT_T2_ENABLE
INIT_T2_SOURCE_PATTERNS
PHASE1_BRAIN_EXTRACT_METHOD
PHASE1_T2_COREG_ENABLE
PHASE1_T2_SURFER_ENABLE
PHASE1_T2_MULTICHANNEL_REG_ENABLE
PHASE1_SUBCORTICAL_MASK_ENABLE
PHASE1_EEG_LEADFIELD_ENABLE
PHASE1_EEG_USE_T2
PHASE1_EEG_CHARM_USE_FS_DIR
PHASE1_EEG_CAP_SOURCE
PHASE1_EEG_CUSTOM_CAP_CSV
PHASE1_EEG_ELECTRODE_COUNT
PHASE1_EEG_REFERENCE_ELECTRODE
PHASE1_EEG_TDCS_SUBSAMPLING
PHASE1_EEG_LEADFIELD_FIELD
PHASE1_REG_AFFINE_ENABLE
PHASE1_FREESURFER_NO_V8
PHASE1_FASTSURFER_VOX_SIZE
FASTSURFER_USE_CUDA
FASTSURFER_CUDA_AUTO_ASSIGN
FASTSURFER_CUDA_SELECTION
FASTSURFER_CUDA_MAX_SELECTED_DEVICES
SIMNIBS_ENV_HOME
SIMNIBS_HOME
SIMNIBS_PYTHON
SIMNIBS_CHARM_CMD
SIMNIBS_PREPARE_TDCS_LEADFIELD_CMD
MNI_T2
MNI_SUBCORTICAL_MASK
```

## Phase Documents

- [phase0_init](./phases/phase0_init.md)
- [phase1_anat](./phases/phase1_anat.md)
- [phase2_fmri](./phases/phase2_fmri.md)
- [phase3_dwi](./phases/phase3_dwi.md)
- [phase4_summary](./phases/phase4_summary.md)
