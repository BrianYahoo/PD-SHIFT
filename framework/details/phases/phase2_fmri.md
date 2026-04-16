# phase2_fmri

代码入口：

```text
script/phases/phase2_fmri.sh
script/phases/phase2_fmri/step*.sh
```

trial 根目录：

```text
phase2_fmri/{trial_name}/
phase2_fmri/stepview/{trial_name}/
phase2_fmri/visualization/{trial_name}/
```

入口会跳过 timepoints < 2 的 trial。

## step1_remove_start_images

### 输入

- `phase0_init/step1_bids_standardize/trials/{trial_name}/func.nii.gz` from phase0 step1

### 输出

```text
phase2_fmri/{trial_name}/func_trim.nii.gz
phase2_fmri/stepview/{trial_name}/step1-1_raw_input.nii.gz
phase2_fmri/stepview/{trial_name}/step1-2_remove_start_images.nii.gz
```

## step2_slice_timing

### 输入

- `phase2_fmri/{trial_name}/func_trim.nii.gz` from phase2 step1
- `phase0_init/step1_bids_standardize/trials/{trial_name}/func.json` from phase0 step1

TR 读取规则：

- 优先读取 `func.json` 中的 `RepetitionTime`。
- `FUNC_REQUIRE_JSON_TR=1` 时缺失即报错。
- `FUNC_REQUIRE_JSON_TR=0` 时才允许使用 `DEFAULT_FUNC_TR` fallback。

### 输出

```text
phase2_fmri/{trial_name}/func_stc.nii.gz
phase2_fmri/stepview/{trial_name}/step2-1_slice_timing_input.nii.gz
phase2_fmri/stepview/{trial_name}/step2-2_slice_timing_output.nii.gz
```

## step3_distortion_correction

### 输入

- `phase2_fmri/{trial_name}/func_stc.nii.gz` from phase2 step2
- `phase0_init/step1_bids_standardize/trials/{trial_name}/func.json` from phase0 step1
- `phase0_init/step1_bids_standardize/trials/{trial_name}/func_ref.nii.gz` from phase0 step1
- `phase0_init/step1_bids_standardize/trials/{trial_name}/func_ref.json` from phase0 step1

### 输出

```text
phase2_fmri/{trial_name}/func_topup.nii.gz
phase2_fmri/{trial_name}/topup_acqparams.txt
phase2_fmri/{trial_name}/topup_b0_main.nii.gz
phase2_fmri/{trial_name}/topup_b0_ref.nii.gz
phase2_fmri/{trial_name}/topup_b0_pair.nii.gz
phase2_fmri/{trial_name}/topup_base*
phase2_fmri/{trial_name}/topup_iout.nii.gz
phase2_fmri/{trial_name}/topup_field.nii.gz
phase2_fmri/{trial_name}/topup.log
phase2_fmri/{trial_name}/applytopup.log
phase2_fmri/stepview/{trial_name}/step3-1_distortion_input.nii.gz
phase2_fmri/stepview/{trial_name}/step3-2_distortion_output.nii.gz
```

如果 topup 条件不满足，只输出复制后的 `func_topup.nii.gz` 和 stepview。

## step4_motion_correction

### 输入

- `phase2_fmri/{trial_name}/func_topup.nii.gz` from phase2 step3

### 输出

```text
phase2_fmri/{trial_name}/func_mc.nii.gz
phase2_fmri/{trial_name}/func_mc.par
phase2_fmri/{trial_name}/func_mean.nii.gz
phase2_fmri/{trial_name}/mcflirt.log
phase2_fmri/visualization/{trial_name}/motion/motion_metrics.png
phase2_fmri/visualization/{trial_name}/motion/framewise_displacement.tsv
phase2_fmri/visualization/{trial_name}/motion/motion_metrics.done
phase2_fmri/stepview/{trial_name}/step4-1_motion_corrected.nii.gz
phase2_fmri/stepview/{trial_name}/step4-2_motion_reference.nii.gz
```

## step5_bbr

### 输入

- `phase2_fmri/{trial_name}/func_mean.nii.gz` from phase2 step4
- `phase1_anat/step1_brain_extract/t1_n4.nii.gz` from phase1 step1
- `phase1_anat/step1_brain_extract/t1_brain.nii.gz` from phase1 step1
- `phase1_anat/step1_brain_extract/t1_brain_mask.nii.gz` from phase1 step1
- `phase1_anat/step2_surfer_recon/aparc+aseg.nii.gz` from phase1 step2
- `phase1_anat/atlas/sub-xxx_desc-custom_dseg.nii.gz` from phase1 step6
- `phase1_anat/atlas/sub-xxx_labels.tsv` from phase1 step6

### 输出

```text
phase2_fmri/{trial_name}/bbr.mat
phase2_fmri/{trial_name}/t1_to_func.mat
phase2_fmri/{trial_name}/atlas_in_func.nii.gz
phase2_fmri/{trial_name}/gs_mask_func_raw.nii.gz
phase2_fmri/{trial_name}/gs_mask_func.nii.gz
phase2_fmri/{trial_name}/wm_mask_t1.nii.gz
phase2_fmri/{trial_name}/wm_mask_func_raw.nii.gz
phase2_fmri/{trial_name}/wm_mask_func.nii.gz
phase2_fmri/{trial_name}/csf_mask_t1.nii.gz
phase2_fmri/{trial_name}/csf_mask_func_raw.nii.gz
phase2_fmri/{trial_name}/csf_mask_func.nii.gz
phase2_fmri/{trial_name}/flirt_*.log
phase2_fmri/visualization/{trial_name}/bbr/t=<frame>/atlas/z=*.png
phase2_fmri/visualization/{trial_name}/bbr/t=<frame>/subcortex/<ROI>/z=*.png
phase2_fmri/visualization/{trial_name}/bbr/split_overlay.done
```

`atlas/` 输出全 z 切片，`subcortex/<ROI>/` 只输出包含该 ROI 的 z 切片。

Stepview：

```text
phase2_fmri/stepview/{trial_name}/step5-1_bbr_reference.nii.gz
phase2_fmri/stepview/{trial_name}/step5-2_atlas_in_func.nii.gz
phase2_fmri/stepview/{trial_name}/step5-3_global_mask.nii.gz
phase2_fmri/stepview/{trial_name}/step5-4_wm_mask.nii.gz
phase2_fmri/stepview/{trial_name}/step5-5_csf_mask.nii.gz
```

## step6_spatially_smooth

### 输入

- `phase2_fmri/{trial_name}/func_mc.nii.gz` from phase2 step4

### 输出

```text
phase2_fmri/{trial_name}/func_smooth.nii.gz
phase2_fmri/stepview/{trial_name}/step6-1_smooth_input.nii.gz
phase2_fmri/stepview/{trial_name}/step6-2_smooth_output.nii.gz
```

## step7_temporally_detrend

### 输入

- `phase2_fmri/{trial_name}/func_smooth.nii.gz` from phase2 step6
- `phase2_fmri/{trial_name}/gs_mask_func.nii.gz` from phase2 step5

### 输出

```text
phase2_fmri/{trial_name}/func_detrend.nii.gz
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_detrend_qc.json
phase2_fmri/stepview/{trial_name}/step7-1_detrend_input.nii.gz
phase2_fmri/stepview/{trial_name}/step7-2_detrend_output.nii.gz
```

## step8_regress_out_covariates

### 输入

- `phase2_fmri/{trial_name}/func_detrend.nii.gz` from phase2 step7
- `phase2_fmri/{trial_name}/func_mc.par` from phase2 step4
- `phase2_fmri/{trial_name}/gs_mask_func.nii.gz` from phase2 step5
- `phase2_fmri/{trial_name}/wm_mask_func.nii.gz` from phase2 step5
- `phase2_fmri/{trial_name}/csf_mask_func.nii.gz` from phase2 step5

### 输出

```text
phase2_fmri/{trial_name}/func_regress.nii.gz
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_regress_qc.json
phase2_fmri/stepview/{trial_name}/step8-1_regress_input.nii.gz
phase2_fmri/stepview/{trial_name}/step8-2_regress_output.nii.gz
```

## step9_temporally_filter

### 输入

- `phase2_fmri/{trial_name}/func_regress.nii.gz` from phase2 step8
- `phase2_fmri/{trial_name}/gs_mask_func.nii.gz` from phase2 step5
- `phase0_init/step1_bids_standardize/trials/{trial_name}/func.json` from phase0 step1

TR 读取规则同 step2。

### 输出

```text
phase2_fmri/{trial_name}/func_filter.nii.gz
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_filter_qc.json
phase2_fmri/stepview/{trial_name}/step9-1_filter_input.nii.gz
phase2_fmri/stepview/{trial_name}/step9-2_filter_output.nii.gz
```

## step10_scrubbing_mark

### 输入

- `phase2_fmri/{trial_name}/func_filter.nii.gz` from phase2 step9
- `phase2_fmri/{trial_name}/func_mc.par` from phase2 step4

### 输出

```text
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FD_power.txt
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_scrub_mask.txt
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_scrub_qc.json
phase2_fmri/{trial_name}/toxic_frames.nii.gz
phase2_fmri/stepview/{trial_name}/step10-1_scrubbing_input.nii.gz
phase2_fmri/stepview/{trial_name}/step10-2_toxic_frames.nii.gz
```

## step11_extract_signal

### 输入

- `phase2_fmri/{trial_name}/func_filter.nii.gz` from phase2 step9
- `phase2_fmri/{trial_name}/atlas_in_func.nii.gz` from phase2 step5
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_detrend_qc.json` from phase2 step7
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_regress_qc.json` from phase2 step8
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_filter_qc.json` from phase2 step9
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_scrub_qc.json` from phase2 step10
- `phase1_anat/atlas/sub-xxx_labels.tsv` from phase1 step6

### 输出

```text
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_pearson.csv
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_fisherz.csv
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_timeseries.tsv
phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_qc.json
phase2_fmri/{trial_name}/manifest.tsv
phase2_fmri/{trial_name}/stepresult/stepwise.done
phase2_fmri/{trial_name}/stepresult/step5_bbr_fc_pearson.csv
phase2_fmri/{trial_name}/stepresult/step5_bbr_fc_fisherz.csv
phase2_fmri/stepview/{trial_name}/step11-1_extract_signal_input.nii.gz
phase2_fmri/stepview/{trial_name}/step11-2_extract_signal_atlas.nii.gz
phase2_fmri/stepview/{trial_name}/stepsignal/
phase2_fmri/stepview/{trial_name}/stepfc/
```
