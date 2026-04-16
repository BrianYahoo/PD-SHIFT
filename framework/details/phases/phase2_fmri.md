# phase2_fmri

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase2_fmri.sh
/data/bryang/project/CNS/pipeline/script/phases/phase2_fmri/step*.sh
```

trial 变量：

```text
FMRI_DIR=${PHASE2_FMRI_DIR}/${trial_name}
FMRI_VIS_DIR=${SUBJECT_WORK_ROOT}/visualization/phase2_fmri/${trial_name}
FMRI_STEPS_DIR=${FMRI_VIS_DIR}/stepview
```

phase2 会跳过 timepoints 小于 2 的 trial。

## step1_remove_start_images

### 输入

```text
${PHASE0_INIT_STEP1_DIR}/trials/${trial_name}/func.nii.gz
```

### 输出

```text
${FMRI_DIR}/func_trim.nii.gz
${FMRI_STEPS_DIR}/step1-1_raw_input.nii.gz
${FMRI_STEPS_DIR}/step1-2_remove_start_images.nii.gz
```

### 工具

```text
FSL fslroi
```

## step2_slice_timing

### 输入

```text
${FMRI_DIR}/func_trim.nii.gz
${PHASE0_INIT_STEP1_DIR}/trials/${trial_name}/func.json
```

### 输出

```text
${FMRI_DIR}/func_stc.nii.gz
${FMRI_STEPS_DIR}/step2-1_slice_timing_input.nii.gz
${FMRI_STEPS_DIR}/step2-2_slice_timing_output.nii.gz
```

### 关键参数

```text
FUNC_REQUIRE_JSON_TR
DEFAULT_FUNC_TR
FMRI_SLICE_TIMING_TR_THRESHOLD
```

## step3_distortion_correction

### 输入

```text
${FMRI_DIR}/func_stc.nii.gz
${PHASE0_INIT_STEP1_DIR}/trials/${trial_name}/func.json
${PHASE0_INIT_STEP1_DIR}/trials/${trial_name}/func_ref.nii.gz
${PHASE0_INIT_STEP1_DIR}/trials/${trial_name}/func_ref.json
```

### 输出

```text
${FMRI_DIR}/func_topup.nii.gz
${FMRI_DIR}/topup_acqparams.txt
${FMRI_DIR}/topup_b0_main.nii.gz
${FMRI_DIR}/topup_b0_ref.nii.gz
${FMRI_DIR}/topup_b0_pair.nii.gz
${FMRI_DIR}/topup_base*
${FMRI_DIR}/topup_iout.nii.gz
${FMRI_DIR}/topup_field.nii.gz
${FMRI_DIR}/topup.log
${FMRI_DIR}/applytopup.log
${FMRI_STEPS_DIR}/step3-1_distortion_input.nii.gz
${FMRI_STEPS_DIR}/step3-2_distortion_output.nii.gz
```

## step4_motion_correction

### 输入

```text
${FMRI_DIR}/func_topup.nii.gz
```

### 输出

```text
${FMRI_DIR}/func_mc.nii.gz
${FMRI_DIR}/func_mc.par
${FMRI_DIR}/func_mean.nii.gz
${FMRI_DIR}/mcflirt.log
${FMRI_VIS_DIR}/motion/motion_metrics.png
${FMRI_VIS_DIR}/motion/framewise_displacement.tsv
${FMRI_VIS_DIR}/motion/motion_metrics.done
${FMRI_STEPS_DIR}/step4-1_motion_corrected.nii.gz
${FMRI_STEPS_DIR}/step4-2_motion_reference.nii.gz
```

## step5_bbr

### 输入

```text
${FMRI_DIR}/func_mean.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_brain_mask.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz
${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv
```

### 输出

```text
${FMRI_DIR}/bbr.mat
${FMRI_DIR}/t1_to_func.mat
${FMRI_DIR}/wmseg_t1.nii.gz
${FMRI_DIR}/atlas_in_func.nii.gz
${FMRI_DIR}/t2_in_func.nii.gz
${FMRI_DIR}/gs_mask_func_raw.nii.gz
${FMRI_DIR}/gs_mask_func.nii.gz
${FMRI_DIR}/wm_mask_t1.nii.gz
${FMRI_DIR}/wm_mask_func_raw.nii.gz
${FMRI_DIR}/wm_mask_func.nii.gz
${FMRI_DIR}/csf_mask_t1.nii.gz
${FMRI_DIR}/csf_mask_func_raw.nii.gz
${FMRI_DIR}/csf_mask_func.nii.gz
${FMRI_DIR}/epi_reg.log
${FMRI_DIR}/flirt_atlas_to_func.log
${FMRI_DIR}/flirt_t2_to_func.log
${FMRI_DIR}/flirt_gs_to_func.log
${FMRI_DIR}/flirt_wm_to_func.log
${FMRI_DIR}/flirt_csf_to_func.log
```

BBR 可视化目录：

```text
${FMRI_VIS_DIR}/bbr/t=10/t1/atlas/z=*.png
${FMRI_VIS_DIR}/bbr/t=10/t1/subcortex/<ROI>/z=*.png
${FMRI_VIS_DIR}/bbr/t=20/t1/atlas/z=*.png
...
${FMRI_VIS_DIR}/bbr/t=100/t1/atlas/z=*.png
${FMRI_VIS_DIR}/bbr/t=100/t1/subcortex/<ROI>/z=*.png
${FMRI_VIS_DIR}/bbr/t=10/t2/atlas/z=*.png
${FMRI_VIS_DIR}/bbr/t=10/t2/subcortex/<ROI>/z=*.png
...
${FMRI_VIS_DIR}/bbr/t=100/t2/atlas/z=*.png
${FMRI_VIS_DIR}/bbr/t=100/t2/subcortex/<ROI>/z=*.png
${FMRI_VIS_DIR}/bbr/split_overlay.done
```

固定 frame 列表：

```text
10,20,30,40,50,60,70,80,90,100
```

subcortex PNG 规则：

- `atlas/` 输出所有 z。
- `subcortex/<ROI>/` 只输出实际包含该 ROI 的 z。

### Stepview

```text
${FMRI_STEPS_DIR}/step5-1_bbr_reference.nii.gz
${FMRI_STEPS_DIR}/step5-2_atlas_in_func.nii.gz
${FMRI_STEPS_DIR}/step5-3_global_mask.nii.gz
${FMRI_STEPS_DIR}/step5-4_wm_mask.nii.gz
${FMRI_STEPS_DIR}/step5-5_csf_mask.nii.gz
${FMRI_STEPS_DIR}/step5-6_t2_in_func.nii.gz
```

## step6_spatially_smooth

### 输入

```text
${FMRI_DIR}/func_mc.nii.gz
```

### 输出

```text
${FMRI_DIR}/func_smooth.nii.gz
${FMRI_STEPS_DIR}/step6-1_smooth_input.nii.gz
${FMRI_STEPS_DIR}/step6-2_smooth_output.nii.gz
```

## step7_temporally_detrend

### 输入

```text
${FMRI_DIR}/func_smooth.nii.gz
${FMRI_DIR}/gs_mask_func.nii.gz
```

### 输出

```text
${FMRI_DIR}/func_detrend.nii.gz
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_detrend_qc.json
${FMRI_STEPS_DIR}/step7-1_detrend_input.nii.gz
${FMRI_STEPS_DIR}/step7-2_detrend_output.nii.gz
```

## step8_regress_out_covariates

### 输入

```text
${FMRI_DIR}/func_detrend.nii.gz
${FMRI_DIR}/func_mc.par
${FMRI_DIR}/gs_mask_func.nii.gz
${FMRI_DIR}/wm_mask_func.nii.gz
${FMRI_DIR}/csf_mask_func.nii.gz
```

### 输出

```text
${FMRI_DIR}/func_regress.nii.gz
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_regress_qc.json
${FMRI_STEPS_DIR}/step8-1_regress_input.nii.gz
${FMRI_STEPS_DIR}/step8-2_regress_output.nii.gz
```

## step9_temporally_filter

### 输入

```text
${FMRI_DIR}/func_regress.nii.gz
${FMRI_DIR}/gs_mask_func.nii.gz
${PHASE0_INIT_STEP1_DIR}/trials/${trial_name}/func.json
```

### 输出

```text
${FMRI_DIR}/func_filter.nii.gz
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_filter_qc.json
${FMRI_STEPS_DIR}/step9-1_filter_input.nii.gz
${FMRI_STEPS_DIR}/step9-2_filter_output.nii.gz
```

## step10_scrubbing_mark

### 输入

```text
${FMRI_DIR}/func_filter.nii.gz
${FMRI_DIR}/func_mc.par
```

### 输出

```text
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_FD_power.txt
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_scrub_mask.txt
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_scrub_qc.json
${FMRI_DIR}/toxic_frames.nii.gz
${FMRI_STEPS_DIR}/step10-1_scrubbing_input.nii.gz
${FMRI_STEPS_DIR}/step10-2_toxic_frames.nii.gz
```

## step11_extract_signal

### 输入

```text
${FMRI_DIR}/func_filter.nii.gz
${FMRI_DIR}/atlas_in_func.nii.gz
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_detrend_qc.json
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_regress_qc.json
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_filter_qc.json
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_scrub_qc.json
${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv
```

### 输出

```text
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_FC_pearson.csv
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_FC_fisherz.csv
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_FC_timeseries.tsv
${FMRI_DIR}/${SUBJECT_ID}_${trial_name}_FC_qc.json
${FMRI_DIR}/manifest.tsv
${FMRI_DIR}/stepresult/stepwise.done
${FMRI_DIR}/stepresult/step5_bbr_fc_pearson.csv
${FMRI_DIR}/stepresult/step5_bbr_fc_fisherz.csv
${FMRI_STEPS_DIR}/step11-1_extract_signal_input.nii.gz
${FMRI_STEPS_DIR}/step11-2_extract_signal_atlas.nii.gz
```

step12 诊断输出位于：

```text
${FMRI_VIS_DIR}/stepview/stepsignal/
${FMRI_VIS_DIR}/stepview/stepfc/
```
