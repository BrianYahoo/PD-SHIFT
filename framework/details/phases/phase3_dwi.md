# phase3_dwi

代码入口：

```text
script/phases/phase3_dwi.sh
script/phases/phase3_dwi/step*.sh
```

DWI 工作目录：

```text
phases/phase3_dwi/
```

## step1_import_raw

### 输入

- `phase0_init/step1_bids_standardize/dwi.nii.gz` from phase0 step1
- `phase0_init/step1_bids_standardize/dwi.bval` from phase0 step1
- `phase0_init/step1_bids_standardize/dwi.bvec` from phase0 step1
- `phase0_init/step1_bids_standardize/dwi.json` from phase0 step1
- `phase0_init/step1_bids_standardize/dwi_rev.nii.gz` from phase0 step1
- `phase0_init/step1_bids_standardize/dwi_rev.bval` from phase0 step1
- `phase0_init/step1_bids_standardize/dwi_rev.bvec` from phase0 step1
- `phase0_init/step1_bids_standardize/dwi_rev.json` from phase0 step1

reverse PE 输入可选。

### 输出

```text
phase3_dwi/dwi_raw.mif
phase3_dwi/dwi_rev_raw.mif
```

## step2_preprocess

### 输入

- `phase3_dwi/dwi_raw.mif` from phase3 step1
- `phase3_dwi/dwi_rev_raw.mif` from phase3 step1

### 输出

```text
phase3_dwi/dwi_denoised.mif
phase3_dwi/noise.mif
phase3_dwi/dwi_den_gibbs.mif
phase3_dwi/dwi_preproc.mif
phase3_dwi/dwi_preproc_bias.mif
phase3_dwi/dwi_bias.mif
phase3_dwi/dwi_mask.mif
phase3_dwi/mean_b0.mif
phase3_dwi/mean_b0.nii.gz
phase3_dwi/data.nii.gz
phase3_dwi/data.bvec
phase3_dwi/data.bval
phase3_dwi/brain_mask.nii.gz
```

## step3_fod

### 输入

- `phase3_dwi/dwi_preproc_bias.mif` from phase3 step2
- `phase3_dwi/dwi_mask.mif` from phase3 step2

### 输出

```text
phase3_dwi/wm_response.txt
phase3_dwi/gm_response.txt
phase3_dwi/csf_response.txt
phase3_dwi/wmfod.mif
phase3_dwi/gmfod.mif
phase3_dwi/csffod.mif
phase3_dwi/wmfod_norm.mif
phase3_dwi/gmfod_norm.mif
phase3_dwi/csffod_norm.mif
```

## step4_registration

### 输入

- `phase3_dwi/mean_b0.nii.gz` from phase3 step2
- `phase1_anat/step1_brain_extract/t1_brain.nii.gz` from phase1 step1
- `phase1_anat/step2_surfer_recon/aparc+aseg.nii.gz` from phase1 step2
- `phase1_anat/atlas/sub-xxx_desc-custom_dseg.nii.gz` from phase1 step6
- `phase1_anat/atlas/sub-xxx_labels.tsv` from phase1 step6

### 输出

```text
phase3_dwi/t1_to_dwi.mat
phase3_dwi/atlas_in_dwi.nii.gz
phase3_dwi/aparc+aseg_int.nii.gz
phase3_dwi/aparc+aseg_dwi.nii.gz
phase3_dwi/FreeSurferColorLUT_mrtrix.txt
phase3_dwi/5tt_dwi.mif
phase3_dwi/5tt_dwi_raw.nii.gz
phase3_dwi/5tt_dwi_fixed.nii.gz
phase3_dwi/5tt_subcgm_fix.json
phase3_dwi/gmwmi_seed.mif
phase3_dwi/flirt_t1_to_dwi.log
phase3_dwi/flirt_atlas_to_dwi.log
phase3_dwi/flirt_aparc_to_dwi.log
phase3_dwi/visualization/registration/dwi/subcortex/<ROI>/z=*.png
phase3_dwi/visualization/registration/dwi/atlas/z=*.png
phase3_dwi/visualization/registration/split_overlay.done
```

`atlas/` 输出全 z 切片，`subcortex/<ROI>/` 只输出包含该 ROI 的 z 切片。

`5tt_dwi_raw.nii.gz`、`5tt_dwi_fixed.nii.gz`、`5tt_subcgm_fix.json` 仅在 `DWI_5TT_FIX_HYBRID_SUBCGM=1` 时生成。

## step5_tractography

### 输入

- `phase3_dwi/wmfod_norm.mif` from phase3 step3
- `phase3_dwi/5tt_dwi.mif` from phase3 step4
- `phase3_dwi/gmwmi_seed.mif` from phase3 step4

### 输出

```text
phase3_dwi/tracks.tck
phase3_dwi/sift2_weights.txt
```

## step6_connectome

### 输入

- `phase3_dwi/tracks.tck` from phase3 step5
- `phase3_dwi/sift2_weights.txt` from phase3 step5
- `phase3_dwi/atlas_in_dwi.nii.gz` from phase3 step4

### 输出

```text
phase3_dwi/sub-xxx_DTI_connectome_sift2.csv
phase3_dwi/sub-xxx_DTI_connectome_count.csv
phase3_dwi/sub-xxx_DTI_connectome_sift2_radial4.csv
phase3_dwi/sub-xxx_DTI_connectome_count_radial4.csv
phase3_dwi/visualization/compare_radial.png
phase3_dwi/manifest.tsv
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
sc_count
sc_sift2_radial4
sc_count_radial4
compare_radial_png
scale_invnodevol_enabled
assignment_radial_search_main
assignment_radial_search_compare
```
