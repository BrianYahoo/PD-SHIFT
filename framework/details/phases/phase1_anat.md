# phase1_anat

代码入口：

```text
script/phases/phase1_anat.sh
```

固定 step：

1. `step1_brain_extract`
2. `step2_surfer_recon`
3. `step3_subcortical_syn`
4. `step4_warpdrive_review`
5. `step5_save_inverse_warp`
6. `step6_distal_inverse_fusion`

## step1_brain_extract

### 输入

- `phase0_init/step1_bids_standardize/t1.nii.gz` from phase0 step1
- `phase0_init/step1_bids_standardize/t1.json` from phase0 step1

### 输出

```text
phase1_anat/step1_brain_extract/manifest.tsv
phase1_anat/step1_brain_extract/t1_n4.nii.gz
phase1_anat/step1_brain_extract/t1_biasfield.nii.gz
phase1_anat/step1_brain_extract/t1_brain.nii.gz
phase1_anat/step1_brain_extract/t1_brain_mask.nii.gz
phase1_anat/step1_brain_extract/t1_freesurfer_xmask.nii.gz
phase1_anat/step1_brain_extract/t1_freesurfer_brain.nii.gz
phase1_anat/step1_brain_extract/n4.log
phase1_anat/step1_brain_extract/bet.log
phase1_anat/step1_brain_extract/synthstrip.log
```

`bet.log` 或 `synthstrip.log` 取决于 `PHASE1_BRAIN_EXTRACT_METHOD`。

### Stepview

```text
phase1_anat/stepview/step1-1_t1_n4.nii.gz
phase1_anat/stepview/step1-2_t1_brain.nii.gz
phase1_anat/stepview/step1-3_t1_brain_mask.nii.gz
phase1_anat/stepview/step1-4_t1_freesurfer_xmask.nii.gz
phase1_anat/stepview/step1-5_t1_freesurfer_brain.nii.gz
```

## step2_surfer_recon

### 输入

FreeSurfer 路径：

- `phase1_anat/step1_brain_extract/t1_n4.nii.gz` from phase1 step1
- `phase1_anat/step1_brain_extract/t1_freesurfer_xmask.nii.gz` from phase1 step1
- `phase1_anat/step1_brain_extract/t1_freesurfer_brain.nii.gz` from phase1 step1

FastSurfer 路径：

- `bids/sub-xxx/anat/sub-xxx_T1w.nii.gz` from phase0 step1
- `phase1_anat/step1_brain_extract/t1_n4.nii.gz` from phase1 step1

共同输入：

- dataset config 中的 `PHASE1_SURFER_HIRES`
- dataset config 中的 FreeSurfer/FastSurfer 专属参数

### 输出

```text
phase1_anat/step2_surfer_recon/manifest.tsv
phase1_anat/step2_surfer_recon/aparc+aseg.nii.gz
phase1_anat/step2_surfer_recon/surfer.done
phase1_anat/step2_surfer_recon/recon-all.log
phase1_anat/step2_surfer_recon/fastsurfer.log
phase1_anat/step2_surfer_recon/recon-all.expert.opts
phase1_anat/step2_surfer_recon/surfer_subjects/sub-xxx/
```

FreeSurfer/FastSurfer subject 关键输出：

```text
surfer_subjects/sub-xxx/mri/orig.mgz
surfer_subjects/sub-xxx/mri/nu.mgz
surfer_subjects/sub-xxx/mri/T1.mgz
surfer_subjects/sub-xxx/mri/brainmask.mgz
surfer_subjects/sub-xxx/mri/aparc+aseg.mgz
surfer_subjects/sub-xxx/surf/lh.white
surfer_subjects/sub-xxx/surf/rh.white
surfer_subjects/sub-xxx/surf/lh.pial
surfer_subjects/sub-xxx/surf/rh.pial
```

FastSurfer 额外关键输出：

```text
surfer_subjects/sub-xxx/mri/aparc.DKTatlas+aseg.deep.mgz
surfer_subjects/sub-xxx/mri/aparc.DKTatlas+aseg.mapped.mgz
surfer_subjects/sub-xxx/mri/orig_nu.mgz
surfer_subjects/sub-xxx/mri/mask.mgz
```

### Manifest 字段

```text
subject_id
surfer_type
surfer_label
bids_t1_input
t1_native_input
t1_brain
t1_brain_mask
t1_freesurfer_xmask
t1_freesurfer_brain
surfer_subjects_dir
surfer_subject_dir
surfer_engine_log
recon_all_args
surfer_hires
fastsurfer_vox_size
t1_resample_voxel_size_mm
recon_all_expert_opts
freesurfer_cortex_label_args
fastsurfer_label_cortex_args
brainmask_mgz
aparc_aseg
```

### Stepview

```text
phase1_anat/stepview/step2-1_surfer_input_t1.nii.gz
phase1_anat/stepview/step2-2_surfer_aux_mask.nii.gz
phase1_anat/stepview/step2-3_aparc_aseg.nii.gz
```

## step3_subcortical_syn

### 输入

- `phase1_anat/step1_brain_extract/t1_brain.nii.gz` from phase1 step1
- `MNI_T1` from config
- `MNI_BRAINMASK` from config
- `DISTAL_ATLAS_DIR` from config
- `SN_ATLAS_DIR` from config
- `config/distal_gpe_gpi_stn_6.tsv`
- `config/sn_2.tsv`

### 输出

```text
phase1_anat/step3_subcortical_syn/manifest.tsv
phase1_anat/step3_subcortical_syn/mni2009b_brain.nii.gz
phase1_anat/step3_subcortical_syn/distal6_mni.nii.gz
phase1_anat/step3_subcortical_syn/distal6_labels.tsv
phase1_anat/step3_subcortical_syn/sn2_mni.nii.gz
phase1_anat/step3_subcortical_syn/sn2_labels.tsv
phase1_anat/step3_subcortical_syn/mni2009b_to_native_0GenericAffine.mat
phase1_anat/step3_subcortical_syn/mni2009b_to_native_1Warp.nii.gz
phase1_anat/step3_subcortical_syn/mni2009b_to_native_1InverseWarp.nii.gz
```

### Stepview

```text
phase1_anat/stepview/step3-1_mni2009b_brain.nii.gz
phase1_anat/stepview/step3-2_distal_mni.nii.gz
phase1_anat/stepview/step3-3_sn_mni.nii.gz
```

## step4_warpdrive_review

### 输入

- `phase1_anat/step3_subcortical_syn/mni2009b_to_native_0GenericAffine.mat` from phase1 step3
- `phase1_anat/step3_subcortical_syn/mni2009b_to_native_1Warp.nii.gz` from phase1 step3

### 输出

```text
phase1_anat/step4_warpdrive_review/manifest.tsv
phase1_anat/step4_warpdrive_review/warpdrive_review.md
phase1_anat/step4_warpdrive_review/warpdrive_review.ok
phase1_anat/step4_warpdrive_review/warpdrive_review.skipped
```

`warpdrive_review.ok` 只在人工复核模式下需要；默认写 `warpdrive_review.skipped`。

## step5_save_inverse_warp

### 输入

- `phase1_anat/step3_subcortical_syn/mni2009b_to_native_0GenericAffine.mat` from phase1 step3
- `phase1_anat/step3_subcortical_syn/mni2009b_to_native_1Warp.nii.gz` from phase1 step3
- `phase1_anat/step3_subcortical_syn/mni2009b_to_native_1InverseWarp.nii.gz` from phase1 step3

### 输出

```text
phase1_anat/step5_save_inverse_warp/manifest.tsv
phase1_anat/step5_save_inverse_warp/mni2009b_to_native_0GenericAffine.mat
phase1_anat/step5_save_inverse_warp/mni2009b_to_native_1Warp.nii.gz
phase1_anat/step5_save_inverse_warp/native_to_mni2009b_1InverseWarp.nii.gz
```

## step6_distal_inverse_fusion

### 输入

- `phase1_anat/step1_brain_extract/t1_n4.nii.gz` from phase1 step1
- `phase1_anat/step2_surfer_recon/aparc+aseg.nii.gz` from phase1 step2
- `phase1_anat/step3_subcortical_syn/distal6_mni.nii.gz` from phase1 step3
- `phase1_anat/step3_subcortical_syn/distal6_labels.tsv` from phase1 step3
- `phase1_anat/step3_subcortical_syn/sn2_mni.nii.gz` from phase1 step3
- `phase1_anat/step3_subcortical_syn/sn2_labels.tsv` from phase1 step3
- `phase1_anat/step5_save_inverse_warp/mni2009b_to_native_0GenericAffine.mat` from phase1 step5
- `phase1_anat/step5_save_inverse_warp/mni2009b_to_native_1Warp.nii.gz` from phase1 step5
- `framework/details/roi.tsv`

### 输出

```text
phase1_anat/step6_distal_inverse_fusion/manifest.tsv
phase1_anat/step6_distal_inverse_fusion/distal6_native.nii.gz
phase1_anat/step6_distal_inverse_fusion/sn2_native.nii.gz
phase1_anat/step6_distal_inverse_fusion/subc20_native.nii.gz
phase1_anat/step6_distal_inverse_fusion/subc20_labels.tsv
phase1_anat/atlas/sub-xxx_desc-custom_dseg.nii.gz
phase1_anat/atlas/sub-xxx_labels.tsv
phase1_anat/visualization/atlas/z=*.png
phase1_anat/visualization/subcortex/<ROI>/z=*.png
```

### Stepview

```text
phase1_anat/stepview/step6-1_distal_native.nii.gz
phase1_anat/stepview/step6-2_sn_native.nii.gz
phase1_anat/stepview/step6-3_subc20_native.nii.gz
phase1_anat/stepview/step6-4_hybrid_atlas.nii.gz
```

### Atlas 定义

最终 Hybrid Atlas 固定 88 ROI：

- 皮层 68 ROI，来自 Desikan。
- 皮层下 20 ROI，来自常规皮层下结构、DISTAL 和 SN 融合。
- ROI 顺序由 `framework/details/roi.tsv` 固定。
