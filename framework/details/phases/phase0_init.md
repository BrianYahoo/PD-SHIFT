# phase0_init

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase0_init.sh
/data/bryang/project/CNS/pipeline/script/phases/phase0_init/step1_bids_standardize.sh
```

当前 phase 只有一个真实 step：

```text
${PHASE0_INIT_DIR}/step1_bids_standardize
```

## step1_bids_standardize

### 输入

配置文件：

```text
/data/bryang/project/CNS/pipeline/config/pipeline.env
/data/bryang/project/CNS/pipeline/config/datasets/hcp.env
/data/bryang/project/CNS/pipeline/config/datasets/parkinson.env
```

HCP 原始输入模式：

```text
${RAW_ROOT}/${SUBJECT_KEY}/unprocessed/3T/T1w_MPR1/
${RAW_ROOT}/${SUBJECT_KEY}/unprocessed/3T/T1w_MPR2/
${RAW_ROOT}/${SUBJECT_KEY}/unprocessed/3T/T2w_SPC1/
${RAW_ROOT}/${SUBJECT_KEY}/unprocessed/3T/T2w_SPC2/
${RAW_ROOT}/${SUBJECT_KEY}/unprocessed/3T/Diffusion/
${RAW_ROOT}/${SUBJECT_KEY}/unprocessed/3T/rfMRI_REST*/
${RAW_ROOT}/${SUBJECT_KEY}/unprocessed/3T/SpinEchoFieldMap*/
```

Parkinson 原始输入模式：

```text
${RAW_ROOT}/${SUBJECT_KEY}/t1_*
${RAW_ROOT}/${SUBJECT_KEY}/T1_*
${RAW_ROOT}/${SUBJECT_KEY}/mprage*
${RAW_ROOT}/${SUBJECT_KEY}/dMRI*
${RAW_ROOT}/${SUBJECT_KEY}/dwi*
${RAW_ROOT}/${SUBJECT_KEY}/restfMRI*
${RAW_ROOT}/${SUBJECT_KEY}/<由 INIT_T2_SOURCE_PATTERNS 命中的 T2 目录>
```

### 核心输出

step 目录：

```text
${PHASE0_INIT_STEP1_DIR}/
```

固定核心文件：

```text
${PHASE0_INIT_STEP1_DIR}/manifest.tsv
${PHASE0_INIT_STEP1_DIR}/func_trials.tsv
${PHASE0_INIT_STEP1_DIR}/t1.nii.gz
${PHASE0_INIT_STEP1_DIR}/t1.json
${PHASE0_INIT_STEP1_DIR}/dwi.nii.gz
${PHASE0_INIT_STEP1_DIR}/dwi.bval
${PHASE0_INIT_STEP1_DIR}/dwi.bvec
${PHASE0_INIT_STEP1_DIR}/dwi.json
```

可选文件：

```text
${PHASE0_INIT_STEP1_DIR}/t1_ori.nii.gz
${PHASE0_INIT_STEP1_DIR}/t2.nii.gz
${PHASE0_INIT_STEP1_DIR}/t2.json
${PHASE0_INIT_STEP1_DIR}/dwi_rev.nii.gz
${PHASE0_INIT_STEP1_DIR}/dwi_rev.bval
${PHASE0_INIT_STEP1_DIR}/dwi_rev.bvec
${PHASE0_INIT_STEP1_DIR}/dwi_rev.json
${PHASE0_INIT_STEP1_DIR}/func.nii.gz
${PHASE0_INIT_STEP1_DIR}/func.json
${PHASE0_INIT_STEP1_DIR}/func_ref.nii.gz
${PHASE0_INIT_STEP1_DIR}/func_ref.json
```

trial 子目录：

```text
${PHASE0_INIT_STEP1_DIR}/trials/<trial_name>/func.nii.gz
${PHASE0_INIT_STEP1_DIR}/trials/<trial_name>/func.json
${PHASE0_INIT_STEP1_DIR}/trials/<trial_name>/func_ref.nii.gz
${PHASE0_INIT_STEP1_DIR}/trials/<trial_name>/func_ref.json
```

标准化追溯目录：

```text
${PHASE0_INIT_STEP1_DIR}/raw_standardized/t1/
${PHASE0_INIT_STEP1_DIR}/raw_standardized/dwi/
${PHASE0_INIT_STEP1_DIR}/raw_standardized/dwi_rev/
${PHASE0_INIT_STEP1_DIR}/raw_standardized/func/<trial_name>/
${PHASE0_INIT_STEP1_DIR}/raw_standardized/func_ref/<trial_name>/
```

T1 重采样产物命名：

```text
${PHASE0_INIT_STEP1_DIR}/raw_standardized/t1/t1_resampled_<slug>mm.nii.gz
```

例如 `0.7 mm` 会写成：

```text
t1_resampled_0p7mm.nii.gz
```

### BIDS 输出

```text
${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.nii.gz
${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.json
${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T2w.nii.gz
${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T2w.json
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.nii.gz
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.bval
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.bvec
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dwi.json
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dir-rev_dwi.nii.gz
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dir-rev_dwi.bval
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dir-rev_dwi.bvec
${BIDS_SUBJECT_DIR}/dwi/${SUBJECT_ID}_dir-rev_dwi.json
${BIDS_SUBJECT_DIR}/func/${SUBJECT_ID}_task-rest_run-*_dir-*_bold.nii.gz
${BIDS_SUBJECT_DIR}/func/${SUBJECT_ID}_task-rest_run-*_dir-*_bold.json
```

`T2w` 和 `dir-rev` 仅在相应输入存在时写出。

### Stepview

```text
${SUBJECT_WORK_ROOT}/visualization/phase0_init/stepview/step1-1_t1_bids_input.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase0_init/stepview/step1-2_dwi_bids_input.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase0_init/stepview/step1-3_dwi_reverse_input.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase0_init/stepview/step1-4_fmri_primary_input.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase0_init/stepview/step1-5_t1_ori.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase0_init/stepview/step1-6_t2_bids_input.nii.gz
```

### Manifest 关键字段

```text
subject_id
dataset_type
raw_standardization_root
t1_source
t1_original_zooms_mm
t1_resampled
t1_resampled_status
t1_resample_enable
t1_resample_config
t1_resample_voxel_size_mm
t2_enable
t2_available
t2_source
dwi_source
dwi_rev_source
func_source
func_ref_source
func_trials_tsv
bids_subject_dir
```

### 关键参数

```text
DATASET_IMPORT_MODE
INIT_T1_RESAMPLE_ENABLE
INIT_T1_RESAMPLE_VOXEL_SIZE
INIT_T2_ENABLE
INIT_T2_SOURCE_PATTERNS
INIT_T2_HCP_DIR_CANDIDATES
INIT_T2_HCP_FILE_PATTERNS
```
