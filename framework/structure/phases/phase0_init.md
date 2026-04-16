# phase0_init - Data Initialization

入口：

- `script/phases/phase0_init.sh`

当前只有一个 step：

1. `step1_bids_standardize.sh`

## step1_bids_standardize

- 这个 step 把原始 T1、可选 T2、DWI（扩散像）和 REST fMRI（静息态功能像）统一整理成 pipeline 标准输入，并同步写成 BIDS（Brain Imaging Data Structure，脑影像标准目录格式）。

工具：

- `dcm2niix`
- FreeSurfer `mri_convert`
- Python、NiBabel
