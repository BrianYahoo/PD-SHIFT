# phase0_init

入口脚本：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase0_init.sh
```

当前只有一个实际 step：

```text
phase0_init/step1_bids_standardize.sh
```

## step1 BIDS 标准化

功能：

- 按 `DATASET_IMPORT_MODE` 选择导入逻辑。
- 统一 T1、DWI、fMRI 的标准化中间文件。
- 写出 BIDS 目录。
- 写出 fMRI trial 清单。
- 按 config 决定是否重采样 T1 到目标体素尺寸。

## Dataset Import Mode

`DATASET_IMPORT_MODE=hcp_nifti`：

- 直接读取 HCP raw NIfTI。
- T1 从 `unprocessed/3T/T1w_MPR1` 或 `T1w_MPR2` 中选择。
- DWI 从 `unprocessed/3T/Diffusion` 中选择。
- fMRI 遍历 `unprocessed/3T/rfMRI_REST*`。
- 反向相位编码参考优先使用对应 `SpinEchoFieldMap_*`。

`DATASET_IMPORT_MODE=parkinson_dicom`：

- 对 T1、DWI、fMRI DICOM 序列运行 `dcm2niix`。
- T1 候选来自 `t1_*`、`T1_*`、`mprage*`。
- DWI 候选来自 `dMRI*`、`dwi*`。
- fMRI 主序列来自 `restfMRI*`，排除 `Ref` 和明显的 SBRef。
- 同一 stem 存在重复序列时，按序列名中的时间 token 和目录名排序，默认选择更早的序列。
- fMRI `SaveB` trial 会查找同 stem 的 `Ref` 序列作为 topup 参考。

## T1 Resampling

T1 重采样完全由 config 控制：

- `INIT_T1_RESAMPLE_ENABLE=1` 开启。
- `INIT_T1_RESAMPLE_VOXEL_SIZE=<mm>` 指定目标分辨率。

当前 dataset 设置：

- HCP：`INIT_T1_RESAMPLE_ENABLE=0`，`INIT_T1_RESAMPLE_VOXEL_SIZE=1`。
- Parkinson：`INIT_T1_RESAMPLE_ENABLE=1`，`INIT_T1_RESAMPLE_VOXEL_SIZE=0.7`。

实现规则：

- 若开启重采样且输入 T1 体素尺寸不等于目标值，则用 `mri_convert -vs <target> <target> <target>` 生成标准化 T1。
- 原始输入另存为 `t1_ori.nii.gz`。
- 重采样产物保存在 `raw_standardized/t1/t1_resampled_<slug>mm.nii.gz`，例如 `t1_resampled_0p7mm.nii.gz`。
- 后续 phase 只读取 `phase0_init/step1_bids_standardize/t1.nii.gz` 和 BIDS T1。

## Completion Guard

step1 的断点检测必须同时满足：

- `manifest.tsv` 存在。
- `func_trials.tsv` 存在。
- 标准化 T1/DWI 文件存在。
- BIDS anat/dwi/func 文件存在。
- `trials/` 目录存在。
- 如果启用 T1 重采样，manifest 中的 `t1_resample_voxel_size_mm` 必须等于当前 config。
- 如果启用 T1 重采样，`t1.nii.gz` 必须已经处于目标体素尺寸。

## Stepview

本 phase 写入：

```text
phase0_init/stepview/step1-1_t1_bids_input.nii.gz
phase0_init/stepview/step1-2_dwi_bids_input.nii.gz
phase0_init/stepview/step1-3_dwi_reverse_input.nii.gz
phase0_init/stepview/step1-4_fmri_primary_input.nii.gz
phase0_init/stepview/step1-5_t1_ori.nii.gz
```
