# phase0_init

代码入口：

```text
script/phases/phase0_init.sh
script/phases/phase0_init/step1_bids_standardize.sh
```

## step1_bids_standardize

### 输入

配置输入：

- `config/pipeline.env`
- `config/datasets/hcp.env` 或 `config/datasets/parkinson.env`

HCP raw 输入：

- `raw/<subject>/unprocessed/3T/T1w_MPR1/` 或 `T1w_MPR2/`
- `raw/<subject>/unprocessed/3T/Diffusion/`
- `raw/<subject>/unprocessed/3T/rfMRI_REST*/`

Parkinson raw 输入：

- `raw/<subject>/t1_*`、`T1_*` 或 `mprage*`
- `raw/<subject>/dMRI*` 或 `dwi*`
- `raw/<subject>/restfMRI*`

### 标准化输出

step 目录：

```text
phases/phase0_init/step1_bids_standardize/
```

核心输出：

```text
manifest.tsv
func_trials.tsv
t1.nii.gz
t1.json
dwi.nii.gz
dwi.bval
dwi.bvec
dwi.json
dwi_rev.nii.gz
dwi_rev.bval
dwi_rev.bvec
dwi_rev.json
func.nii.gz
func.json
func_ref.nii.gz
func_ref.json
```

可选原始 T1 保留：

```text
t1_ori.nii.gz
```

trial 输出：

```text
trials/{trial_name}/func.nii.gz
trials/{trial_name}/func.json
trials/{trial_name}/func_ref.nii.gz
trials/{trial_name}/func_ref.json
```

转换追溯目录：

```text
raw_standardized/t1/
raw_standardized/dwi/
raw_standardized/dwi_rev/
raw_standardized/func/{trial_name}/
raw_standardized/func_ref/{trial_name}/
```

### BIDS 输出

```text
bids/sub-xxx/anat/sub-xxx_T1w.nii.gz
bids/sub-xxx/anat/sub-xxx_T1w.json
bids/sub-xxx/dwi/sub-xxx_dwi.nii.gz
bids/sub-xxx/dwi/sub-xxx_dwi.bval
bids/sub-xxx/dwi/sub-xxx_dwi.bvec
bids/sub-xxx/dwi/sub-xxx_dwi.json
bids/sub-xxx/dwi/sub-xxx_dir-rev_dwi.nii.gz
bids/sub-xxx/dwi/sub-xxx_dir-rev_dwi.bval
bids/sub-xxx/dwi/sub-xxx_dir-rev_dwi.bvec
bids/sub-xxx/dwi/sub-xxx_dir-rev_dwi.json
bids/sub-xxx/func/sub-xxx_task-rest_run-*_dir-*_bold.nii.gz
bids/sub-xxx/func/sub-xxx_task-rest_run-*_dir-*_bold.json
```

### Manifest 字段

```text
subject_id
dataset_type
raw_standardization_root
t1_source
t1_original_zooms_mm
t1_resampled
t1_resampled_to_1mm
t1_resample_enable
t1_resample_config
t1_resample_voxel_size_mm
dwi_source
dwi_rev_source
func_source
func_ref_source
func_trials_tsv
bids_subject_dir
```

`t1_resampled_to_1mm` 是兼容旧字段名；当前新逻辑以 `t1_resample_enable` 和 `t1_resample_voxel_size_mm` 为准。

### Stepview

```text
phase0_init/stepview/step1-1_t1_bids_input.nii.gz
phase0_init/stepview/step1-2_dwi_bids_input.nii.gz
phase0_init/stepview/step1-3_dwi_reverse_input.nii.gz
phase0_init/stepview/step1-4_fmri_primary_input.nii.gz
phase0_init/stepview/step1-5_t1_ori.nii.gz
```

### 下游读取

phase1 读取：

- `t1.nii.gz`
- `t1.json`
- BIDS T1

phase2 读取：

- `trials/{trial_name}/func.nii.gz`
- `trials/{trial_name}/func.json`
- `trials/{trial_name}/func_ref.nii.gz`
- `trials/{trial_name}/func_ref.json`
- `func_trials.tsv`

phase3 读取：

- `dwi.nii.gz`
- `dwi.bval`
- `dwi.bvec`
- `dwi.json`
- reverse PE 文件如果存在则读取。
