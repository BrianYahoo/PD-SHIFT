# phase2_fmri

入口脚本：

- `script/phases/phase2_fmri.sh`

phase2 会遍历 phase0 写出的 REST trial；只有可处理的 4D trial 会继续进入预处理。

固定 step：

1. `step1_remove_start_images`
2. `step2_slice_timing`
3. `step3_distortion_correction`
4. `step4_motion_correction`
5. `step5_bbr`
6. `step6_spatially_smooth`
7. `step7_temporally_detrend`
8. `step8_regress_out_covariates`
9. `step9_temporally_filter`
10. `step10_scrubbing_mark`
11. `step11_extract_signal`

内部诊断：

- `step12_stepwise_diagnostics`

## step1_remove_start_images

功能：

- 去掉开头 dummy volumes。

关键参数：

- `DUMMY_VOLUMES`

工具：

- FSL `fslroi`

## step2_slice_timing

功能：

- 根据 TR 决定是否做 slice timing。
- 当 `FUNC_REQUIRE_JSON_TR=1` 时，TR 必须来自 JSON。

关键参数：

- `FUNC_REQUIRE_JSON_TR`
- `DEFAULT_FUNC_TR`
- `FMRI_SLICE_TIMING_TR_THRESHOLD`

工具：

- Python、NiBabel、SciPy

## step3_distortion_correction

功能：

- 满足条件时做 topup。
- 不满足条件时直接透传。

关键参数：

- `FMRI_DO_TOPUP`
- `DEFAULT_TOTAL_READOUT_TIME`

工具：

- FSL `topup`
- FSL `applytopup`

## step4_motion_correction

功能：

- 做刚体头动校正。
- 生成 mean image、运动参数、FD 和 motion 图。

工具：

- FSL `mcflirt`
- FSL `fslmaths`
- Python plotting utils

## step5_bbr

功能：

- 用 `epi_reg` 把 mean fMRI 与 native T1 对齐。
- 投影 atlas、GS/WM/CSF mask 到 func 空间。
- 可选把 T2 也投到 func 空间。
- 生成 t1 与 t2 两套 overlay，可同时检查 atlas 和 subcortex。

关键参数：

- 无单独 dataset 分支，完全取决于是否已有 T2 产物

工具：

- FSL `epi_reg`
- FSL `convert_xfm`
- FSL `flirt`
- FSL `fslmaths`
- Python `visualize_registration_overlay.py`

## step6_spatially_smooth

功能：

- 按 FWHM 做空间平滑，或在 `0 mm` 时跳过。

关键参数：

- `FMRI_SMOOTH_FWHM_MM`

工具：

- FSL `fslmaths`

## step7_temporally_detrend

功能：

- 做时间维去趋势。

关键参数：

- `FMRI_DETREND_ORDER`

工具：

- Python utils

## step8_regress_out_covariates

功能：

- 回归 WM、CSF、head motion，可选 GS。

关键参数：

- `FMRI_REGRESS_GS`
- `FMRI_REGRESS_WM`
- `FMRI_REGRESS_CSF`
- `FMRI_REGRESS_HM`
- `FMRI_HM_MODEL`

工具：

- Python utils

## step9_temporally_filter

功能：

- 做带通滤波。

关键参数：

- `FMRI_LOW_CUT_HZ`
- `FMRI_HIGH_CUT_HZ`

工具：

- Python utils

## step10_scrubbing_mark

功能：

- 根据 FD 标记 toxic frames。
- 默认只标记，不真正删除时间点。

关键参数：

- `FMRI_ENABLE_SCRUBBING`
- `FMRI_FD_THRESHOLD`

工具：

- Python utils

## step11_extract_signal

功能：

- 从最终滤波后数据提取 88 ROI timeseries。
- 计算 Pearson 和 Fisher-z FC。
- 写 trial manifest。
- 调用内部 step12，输出逐步诊断信号和 step5 BBR FC。

工具：

- Python `fmri_extract_signal.py`
- Python stepwise diagnostics 工具
