# phase0_init

入口脚本：

- `script/phases/phase0_init.sh`
- `script/phases/phase0_init/step1_bids_standardize.sh`

## step1_bids_standardize

功能：

- 按 `DATASET_IMPORT_MODE` 选择 HCP NIfTI 导入或 Parkinson DICOM 导入。
- 统一输出标准化的 T1、可选 T2、DWI、reverse PE DWI、REST fMRI 和参考 fMRI。
- 统一写 BIDS。
- 统一写 trial 清单，供 phase2 遍历。

概念输入：

- 原始 T1
- 可选原始 T2
- 原始 DWI
- 可选 reverse PE DWI
- 一个或多个 REST fMRI trial

概念输出：

- 标准化后的 anatomical / dwi / func 输入
- BIDS `T1w` / `T2w` / `dwi` / `bold`
- trial manifest

关键参数：

- `DATASET_IMPORT_MODE`
- `INIT_T1_RESAMPLE_ENABLE`
- `INIT_T1_RESAMPLE_VOXEL_SIZE`
- `INIT_T2_ENABLE`
- `INIT_T2_SOURCE_PATTERNS`

实现细节：

- Parkinson 在重复序列间默认选更早的那条。
- T1 重采样由 config 控制，不再写死 1 mm 或 dataset 分支。
- T2 是否进入后续 pipeline，完全由 config 决定。

工具：

- `dcm2niix`
- FreeSurfer `mri_convert`
- Python、NiBabel
