# phase2_fmri - Functional Connectivity

入口：

- `script/phases/phase2_fmri.sh`

固定 step 顺序：

1. `step1_remove_start_images.sh`
2. `step2_slice_timing.sh`
3. `step3_distortion_correction.sh`
4. `step4_motion_correction.sh`
5. `step5_bbr.sh`
6. `step6_spatially_smooth.sh`
7. `step7_temporally_detrend.sh`
8. `step8_regress_out_covariates.sh`
9. `step9_temporally_filter.sh`
10. `step10_scrubbing_mark.sh`
11. `step11_extract_signal.sh`

内部诊断：

- `step12_stepwise_diagnostics.sh`

## step1_remove_start_images

- 这个 step 删除 fMRI 开头的 dummy volumes（未稳定体积）。

工具：

- FSL `fslroi`

## step2_slice_timing

- 这个 step 按 TR（重复时间，fMRI 每一帧采样间隔）决定是否执行 slice timing（层间采样时序校正）。

工具：

- Python、NiBabel、SciPy

## step3_distortion_correction

- 这个 step 在满足条件时执行 topup / applytopup（利用反向相位编码做畸变校正），否则直接透传。

工具：

- FSL `topup`、`applytopup`

## step4_motion_correction

- 这个 step 做刚体头动校正，并生成 mean image 和运动质量控制图。

工具：

- FSL `mcflirt`
- FSL `fslmaths`

## step5_bbr

- 这个 step 用 BBR（Boundary-Based Registration，基于灰白质边界的配准）把 fMRI 对齐到 T1，并把 atlas（分区模板）与掩膜投到 func（功能像）空间。

工具：

- FSL `epi_reg`
- FSL `flirt`
- FSL `convert_xfm`
- FSL `fslmaths`
- Python `visualize_registration_overlay.py`

## step6_spatially_smooth

- 这个 step 按配置对 fMRI 做空间平滑。

工具：

- FSL `fslmaths`

## step7_temporally_detrend

- 这个 step 对 fMRI 时间序列做去趋势。

工具：

- Python utils

## step8_regress_out_covariates

- 这个 step 回归 WM、CSF 和 head motion（头动参数），并可选回归 global signal（全局信号）。

工具：

- Python utils

## step9_temporally_filter

- 这个 step 对 fMRI 时间序列做带通滤波。

工具：

- Python utils

## step10_scrubbing_mark

- 这个 step 计算 FD（Framewise Displacement，逐帧位移）并标记坏帧。

工具：

- Python utils

## step11_extract_signal

- 这个 step 从 88 ROI atlas 中提取时间序列并计算 Pearson / Fisher-z FC（功能连接）矩阵。

工具：

- Python `fmri_extract_signal.py`
- Python `step12_stepwise_diagnostics.sh` 内部工具链
