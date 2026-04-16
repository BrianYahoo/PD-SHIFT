# phase3_dwi

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase3_dwi.sh
/data/bryang/project/CNS/pipeline/script/phases/phase3_dwi/step*.sh
```

DWI 主目录：

```text
${PHASE3_DWI_DIR}/
```

## step1_import_raw

### 输入

```text
${PHASE0_INIT_STEP1_DIR}/dwi.nii.gz
${PHASE0_INIT_STEP1_DIR}/dwi.bval
${PHASE0_INIT_STEP1_DIR}/dwi.bvec
${PHASE0_INIT_STEP1_DIR}/dwi.json
${PHASE0_INIT_STEP1_DIR}/dwi_rev.nii.gz
${PHASE0_INIT_STEP1_DIR}/dwi_rev.bval
${PHASE0_INIT_STEP1_DIR}/dwi_rev.bvec
${PHASE0_INIT_STEP1_DIR}/dwi_rev.json
```

### 输出

```text
${PHASE3_DWI_DIR}/dwi_raw.mif
${PHASE3_DWI_DIR}/dwi_rev_raw.mif
```

## step2_preprocess

### 输入

```text
${PHASE3_DWI_DIR}/dwi_raw.mif
${PHASE3_DWI_DIR}/dwi_rev_raw.mif
```

### 输出

```text
${PHASE3_DWI_DIR}/dwi_denoised.mif
${PHASE3_DWI_DIR}/noise.mif
${PHASE3_DWI_DIR}/dwi_den_gibbs.mif
${PHASE3_DWI_DIR}/dwi_preproc.mif
${PHASE3_DWI_DIR}/dwi_preproc_bias.mif
${PHASE3_DWI_DIR}/dwi_bias.mif
${PHASE3_DWI_DIR}/dwi_mask.mif
${PHASE3_DWI_DIR}/mean_b0.mif
${PHASE3_DWI_DIR}/mean_b0.nii.gz
${PHASE3_DWI_DIR}/data.nii.gz
${PHASE3_DWI_DIR}/data.bvec
${PHASE3_DWI_DIR}/data.bval
${PHASE3_DWI_DIR}/brain_mask.nii.gz
```

## step3_fod

### 输入

```text
${PHASE3_DWI_DIR}/dwi_preproc_bias.mif
${PHASE3_DWI_DIR}/dwi_mask.mif
```

### 输出

```text
${PHASE3_DWI_DIR}/wm_response.txt
${PHASE3_DWI_DIR}/gm_response.txt
${PHASE3_DWI_DIR}/csf_response.txt
${PHASE3_DWI_DIR}/wmfod.mif
${PHASE3_DWI_DIR}/gmfod.mif
${PHASE3_DWI_DIR}/csffod.mif
${PHASE3_DWI_DIR}/wmfod_norm.mif
${PHASE3_DWI_DIR}/gmfod_norm.mif
${PHASE3_DWI_DIR}/csffod_norm.mif
```

## step4_registration

### 输入

```text
${PHASE3_DWI_DIR}/mean_b0.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz
${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv
```

### 输出

```text
${PHASE3_DWI_DIR}/t1_to_dwi.mat
${PHASE3_DWI_DIR}/atlas_in_dwi.nii.gz
${PHASE3_DWI_DIR}/t2_in_dwi.nii.gz
${PHASE3_DWI_DIR}/aparc+aseg_int.nii.gz
${PHASE3_DWI_DIR}/aparc+aseg_dwi.nii.gz
${PHASE3_DWI_DIR}/FreeSurferColorLUT_mrtrix.txt
${PHASE3_DWI_DIR}/5tt_dwi.mif
${PHASE3_DWI_DIR}/5tt_dwi_raw.nii.gz
${PHASE3_DWI_DIR}/5tt_dwi_fixed.nii.gz
${PHASE3_DWI_DIR}/5tt_subcgm_fix.json
${PHASE3_DWI_DIR}/gmwmi_seed.mif
${PHASE3_DWI_DIR}/flirt_t1_to_dwi.log
${PHASE3_DWI_DIR}/flirt_atlas_to_dwi.log
${PHASE3_DWI_DIR}/flirt_t2_to_dwi.log
${PHASE3_DWI_DIR}/flirt_aparc_to_dwi.log
```

registration 可视化：

```text
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/registration/dwi/t1/atlas/z=*.png
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/registration/dwi/t1/subcortex/<ROI>/z=*.png
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/registration/dwi/t2/atlas/z=*.png
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/registration/dwi/t2/subcortex/<ROI>/z=*.png
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/registration/split_overlay.done
```

规则：

- `atlas/` 输出全 z。
- `subcortex/<ROI>/` 只输出含该 ROI 的 z。

### 关键参数

```text
DWI_5TT_FIX_HYBRID_SUBCGM
```

## step5_tractography

### 输入

```text
${PHASE3_DWI_DIR}/wmfod_norm.mif
${PHASE3_DWI_DIR}/5tt_dwi.mif
${PHASE3_DWI_DIR}/gmwmi_seed.mif
```

### 输出

```text
${PHASE3_DWI_DIR}/tracks.tck
${PHASE3_DWI_DIR}/sift2_weights.txt
```

## step6_connectome

### 输入

```text
${PHASE3_DWI_DIR}/tracks.tck
${PHASE3_DWI_DIR}/sift2_weights.txt
${PHASE3_DWI_DIR}/atlas_in_dwi.nii.gz
```

### 输出

```text
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv
${PHASE3_DWI_DIR}/manifest.tsv
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/compare_radial.png
${SUBJECT_WORK_ROOT}/visualization/phase3_dwi/compare_radial_invnodevol.png
```

### Manifest 字段

```text
subject_id
dwi_input
dwi_preproc
atlas_in_dwi
tracks
sift2_weights
sc_sift2
sc_sift2_invnodevol
sc_count
sc_count_invnodevol
sc_sift2_radial4
sc_sift2_invnodevol_radial4
sc_count_radial4
sc_count_invnodevol_radial4
compare_radial_png
compare_radial_invnodevol_png
sc_variants
assignment_radial_search_main
assignment_radial_search_compare
```
