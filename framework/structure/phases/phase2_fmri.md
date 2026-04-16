# phase2_fmri

入口脚本：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase2_fmri.sh
```

入口会读取 `phase0_init/step1_bids_standardize/trials/` 下的 REST trial。只有 4D 且 timepoints >= 2 的 trial 会进入预处理；Ref-only 或单 volume trial 会记录 skip 并继续。

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

`step12_stepwise_diagnostics.sh` 是 step11 依赖的诊断输出，用于生成中间步骤 ROI 信号和 BBR FC 对照结果。

## step1 Remove Start Images

工具：FSL `fslroi`

功能：

- 从 raw fMRI trial 中删除前导 volume。
- `DUMMY_VOLUMES=10` 控制删除数量。
- 如果原始 timepoints 不足以删除，则保留原始输入。

## step2 Slice Timing

工具：Python、NiBabel、NumPy、SciPy

功能：

- 根据 JSON 读取 TR。
- 如果 `FUNC_REQUIRE_JSON_TR=1`，`RepetitionTime` 缺失会直接报错，不使用 `DEFAULT_FUNC_TR` fallback。
- `TR > FMRI_SLICE_TIMING_TR_THRESHOLD` 时执行 slice timing。
- 默认阈值 `FMRI_SLICE_TIMING_TR_THRESHOLD=1.0`。
- 未达到阈值时直接复制输入为输出。

## step3 Distortion Correction

工具：FSL `topup`、`applytopup`

功能：

- 当 `FMRI_DO_TOPUP=1` 且主 fMRI 与 reference PE 方向相反时执行 topup。
- 不满足条件时直接复制输入为 `func_topup.nii.gz`。

## step4 Motion Correction

工具：FSL `mcflirt`、`fslmaths`

功能：

- 对 `func_topup.nii.gz` 做刚体头动校正。
- 输出 `func_mc.nii.gz`、`func_mc.par`、`func_mean.nii.gz`。
- 同时输出 motion PNG 和 FD TSV 到 `phase2_fmri/visualization/<trial>/motion/`。

## step5 BBR

工具：FSL `flirt`、`fslmaths`

功能：

- 将 `func_mean` 配准到 native T1。
- 生成 `bbr.mat` 和 `t1_to_func.mat`。
- 将 88 ROI atlas、global mask、WM mask、CSF mask 投到 func 空间。
- 输出 BBR 可视化到 `phase2_fmri/visualization/<trial>/bbr/`，其中 atlas 和 subcortex overlay 分子目录保存。
- subcortex overlay 每个 ROI 只输出实际包含该 ROI 的 z 切片，避免无目标脑区的空白切片污染检查。

## step6 Spatially Smooth

工具：FSL `fslmaths`

功能：

- `FMRI_SMOOTH_FWHM_MM=0` 时不实际平滑，只复制输入。
- 非 0 时按 FWHM 转 sigma 后执行平滑。

## step7 Temporally Detrend

工具：Python utils

功能：

- 对 `func_smooth.nii.gz` 去趋势。
- `FMRI_DETREND_ORDER=1` 控制去趋势阶数。
- 输出 detrend QC JSON。

## step8 Regress Out Covariates

工具：Python utils

功能：

- 对 `func_detrend.nii.gz` 做协变量回归。
- 默认回归 WM、CSF、head motion。
- 默认不回归 global signal。

关键 config：

- `FMRI_REGRESS_GS=0`
- `FMRI_REGRESS_WM=1`
- `FMRI_REGRESS_CSF=1`
- `FMRI_REGRESS_HM=1`
- `FMRI_HM_MODEL=24`

## step9 Temporally Filter

工具：Python utils

功能：

- 对 `func_regress.nii.gz` 做带通滤波。
- 默认 `FMRI_LOW_CUT_HZ=0.01`，`FMRI_HIGH_CUT_HZ=0.10`。
- TR 来源同 step2：优先读取 trial `func.json` 的 `RepetitionTime`；`FUNC_REQUIRE_JSON_TR=1` 时不允许 fallback。

## step10 Scrubbing

工具：Python utils

功能：

- 从 `func_mc.par` 计算 FD。
- 输出 scrub mask 和 QC。
- 默认 `FMRI_ENABLE_SCRUBBING=0`，因此只记录标记，不删除帧。
- 默认 `FMRI_FD_THRESHOLD=0.5`。

## step11 Extract Signal

工具：Python utils

功能：

- 从 `func_filter.nii.gz` 和 `atlas_in_func.nii.gz` 提取 88 ROI timeseries。
- 输出 Pearson FC、Fisher-z FC、timeseries、QC。
- 触发 stepwise diagnostics，输出各中间步骤的 ROI 信号与 step5 BBR FC。
