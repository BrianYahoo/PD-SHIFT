# phase1_anat

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat.sh
```

固定 step：

1. `step1_brain_extract`
2. `step2_surfer_recon`
3. `step3_subcortical_syn`
4. `step4_warpdrive_review`
5. `step5_save_inverse_warp`
6. `step6_distal_inverse_fusion`
7. `step7_t1t2_myelin`

## step1_brain_extract

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step1_brain_extract.sh
```

### 输入

```text
${PHASE0_INIT_STEP1_DIR}/t1.nii.gz
${PHASE0_INIT_STEP1_DIR}/t2.nii.gz
${PHASE0_INIT_STEP1_DIR}/manifest.tsv
```

### 输出

```text
${PHASE1_ANAT_STEP1_DIR}/manifest.tsv
${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_biasfield.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_brain_mask.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_xmask.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/n4.log
${PHASE1_ANAT_STEP1_DIR}/bet.log
${PHASE1_ANAT_STEP1_DIR}/synthstrip.log
${PHASE1_ANAT_STEP1_DIR}/t2_n4.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_biasfield.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_to_t1.mat
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_n4.log
${PHASE1_ANAT_STEP1_DIR}/flirt_t2_to_t1.log
```

T2 相关输出只在 `PHASE1_T2_COREG_ENABLE=1` 且 phase0 确实有 T2 时存在。

### Stepview

```text
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-1_t1_n4.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-2_t1_brain.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-3_t1_brain_mask.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-4_t1_freesurfer_xmask.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-5_t1_freesurfer_brain.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-6_t2_n4.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-7_t2_coreg_t1.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step1-8_t2_coreg_t1_brain.nii.gz
```

### 关键参数

```text
PHASE1_BRAIN_EXTRACT_METHOD
PHASE1_BET_F
PHASE1_FS_XMASK_DILATIONS
PHASE1_T2_COREG_ENABLE
```

### 工具

```text
ANTs N4BiasFieldCorrection
FSL bet
FSL flirt
FSL fslmaths
FreeSurfer mri_synthstrip
```

## step2_surfer_recon

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step2_surfer_recon.sh
```

### 输入

FreeSurfer / FastSurfer 共用：

```text
${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_brain_mask.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_xmask.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t1_freesurfer_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz
${BIDS_SUBJECT_DIR}/anat/${SUBJECT_ID}_T1w.nii.gz
${PHASE0_INIT_STEP1_DIR}/manifest.tsv
```

### 输出

```text
${PHASE1_ANAT_STEP2_DIR}/manifest.tsv
${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz
${PHASE1_ANAT_STEP2_DIR}/surfer.done
${PHASE1_ANAT_STEP2_DIR}/recon-all.log
${PHASE1_ANAT_STEP2_DIR}/fastsurfer.log
${PHASE1_ANAT_STEP2_DIR}/recon-all.expert.opts
${PHASE1_ANAT_STEP2_DIR}/mri_aparc2aseg.log
${PHASE1_ANAT_STEP2_DIR}/mri_convert.log
${PHASE1_ANAT_STEP2_DIR}/mri_convert_brainmask.log
${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_brainmask.log
${PHASE1_ANAT_STEP2_DIR}/mri_vol2vol_aparc_native.log
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/
```

subject 目录关键文件：

```text
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/orig.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/nu.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/T1.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/brainmask.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/aparc+aseg.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.white
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.white
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.pial
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.pial
```

FastSurfer 专有关键文件：

```text
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/aparc.DKTatlas+aseg.deep.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/aparc.DKTatlas+aseg.mapped.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/orig_nu.mgz
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/mri/mask.mgz
```

### Stepview

```text
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step2-1_surfer_input_t1.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step2-2_surfer_aux_mask.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step2-3_aparc_aseg.nii.gz
```

### FreeSurfer 关键参数

真实命令核心：

```text
recon-all -all -noskullstrip -xmask <t1_freesurfer_xmask> -openmp <NTHREADS>
```

附加参数触发条件：

```text
-hires                         当输入体素任一轴 < 1.0 mm 或 PHASE1_SURFER_HIRES=1
-T2 <t2_coreg_t1> -T2pial     当 PHASE1_T2_SURFER_ENABLE=1 且 T2 存在
-expert recon-all.expert.opts 当 PHASE1_FREESURFER_CORTEX_LABEL_ARGS 非空
-no-v8                        当 PHASE1_FREESURFER_NO_V8=1
```

### FastSurfer 关键参数

真实 full run 核心：

```text
run_fastsurfer.sh --sid --sd --t1 --threads --device --viewagg_device --parallel --py
```

可选参数：

```text
--t2 <t2_coreg_t1> --reg_mode none
--vox_size <PHASE1_FASTSURFER_VOX_SIZE>
--surf_only --edits
```

### Manifest 关键字段

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
surfer_hires_reason
surfer_use_t2
fastsurfer_vox_size
t1_resample_voxel_size_mm
recon_all_expert_opts
freesurfer_cortex_label_args
fastsurfer_label_cortex_args
brainmask_mgz
aparc_aseg
```

## step3_subcortical_syn

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step3_subcortical_syn.sh
```

### 输入

```text
${PHASE1_ANAT_STEP1_DIR}/t1_brain.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz
${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz
${MNI_T1}
${MNI_BRAINMASK}
${MNI_T2}
${MNI_SUBCORTICAL_MASK}
${DISTAL_ATLAS_DIR}
${SN_ATLAS_DIR}
/data/bryang/project/CNS/pipeline/config/distal_gpe_gpi_stn_6.tsv
/data/bryang/project/CNS/pipeline/config/sn_2.tsv
```

### 输出

```text
${PHASE1_ANAT_STEP3_DIR}/manifest.tsv
${PHASE1_ANAT_STEP3_DIR}/mni2009b_brain.nii.gz
${PHASE1_ANAT_STEP3_DIR}/mni2009b_t2_brain.nii.gz
${PHASE1_ANAT_STEP3_DIR}/mni2009b_subcortical_mask.nii.gz
${PHASE1_ANAT_STEP3_DIR}/native_subcortical_mask.nii.gz
${PHASE1_ANAT_STEP3_DIR}/distal6_mni.nii.gz
${PHASE1_ANAT_STEP3_DIR}/distal6_labels.tsv
${PHASE1_ANAT_STEP3_DIR}/sn2_mni.nii.gz
${PHASE1_ANAT_STEP3_DIR}/sn2_labels.tsv
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_0GenericAffine.mat
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_1Warp.nii.gz
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_1InverseWarp.nii.gz
${PHASE1_ANAT_STEP3_DIR}/ants_syn.log
```

native subcortical mask 中实际从 `aparc+aseg` 取用的标签区间：

```text
9.5-13.5   左侧基底节主区
15.5-16.5  brainstem
25.5-28.5  左侧额外深部区
48.5-52.5  右侧基底节主区
57.5-60.5  右侧额外深部区
```

最终做：

```text
-bin -dilM -dilM
```

### Stepview

根据是否启用 T2 与 mask，stepview 序号会有所不同，但产物来源固定来自：

```text
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step3-*_mni2009b_brain.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step3-*_mni2009b_t2_brain.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step3-*_t2_coreg_t1_brain.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step3-*_mni_subcortical_mask.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step3-*_native_subcortical_mask.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step3-*_distal_mni.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step3-*_sn_mni.nii.gz
```

### 配准模式

单通道：

```text
Rigid -> [可选 Affine] -> SyN
metric: MI + CC on T1
```

双通道：

```text
Rigid -> [可选 Affine] -> SyN
metric: MI + CC on T1 and T2
```

mask 模式：

```text
--masks "[${NATIVE_SUBCORTICAL_MASK},${MNI_SUBCORTICAL_MASK_NATIVE}]"
```

### Manifest 关键字段

```text
registration_engine
registration_mode
registration_use_t2
registration_reason
registration_use_affine
affine_reason
registration_use_mask
registration_mask_mode
mask_reason
locked_preset
fixed_image
fixed_t2_image
moving_image
mni_t2
mni_t2_brain
mni_subcortical_mask
mni_subcortical_mask_prepared
native_subcortical_mask
distal_mni
distal_labels
sn_mni
sn_labels
forward_affine
forward_warp
inverse_warp
```

## step4_warpdrive_review

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step4_warpdrive_review.sh
```

### 输入

```text
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_0GenericAffine.mat
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_1Warp.nii.gz
```

### 输出

```text
${PHASE1_ANAT_STEP4_DIR}/manifest.tsv
${PHASE1_ANAT_STEP4_DIR}/warpdrive_review.md
${PHASE1_ANAT_STEP4_DIR}/warpdrive_review.ok
${PHASE1_ANAT_STEP4_DIR}/warpdrive_review.skipped
```

## step5_save_inverse_warp

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step5_save_inverse_warp.sh
```

### 输入

```text
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_0GenericAffine.mat
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_1Warp.nii.gz
${PHASE1_ANAT_STEP3_DIR}/mni2009b_to_native_1InverseWarp.nii.gz
```

### 输出

```text
${PHASE1_ANAT_STEP5_DIR}/manifest.tsv
${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_0GenericAffine.mat
${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_1Warp.nii.gz
${PHASE1_ANAT_STEP5_DIR}/native_to_mni2009b_1InverseWarp.nii.gz
```

## step6_distal_inverse_fusion

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step6_distal_inverse_fusion.sh
```

### 输入

```text
${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1_brain.nii.gz
${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz
${PHASE1_ANAT_STEP3_DIR}/distal6_mni.nii.gz
${PHASE1_ANAT_STEP3_DIR}/distal6_labels.tsv
${PHASE1_ANAT_STEP3_DIR}/sn2_mni.nii.gz
${PHASE1_ANAT_STEP3_DIR}/sn2_labels.tsv
${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_0GenericAffine.mat
${PHASE1_ANAT_STEP5_DIR}/mni2009b_to_native_1Warp.nii.gz
/data/bryang/project/CNS/pipeline/framework/details/roi.tsv
```

### 输出

```text
${PHASE1_ANAT_STEP6_DIR}/manifest.tsv
${PHASE1_ANAT_STEP6_DIR}/distal6_native.nii.gz
${PHASE1_ANAT_STEP6_DIR}/sn2_native.nii.gz
${PHASE1_ANAT_STEP6_DIR}/subc20_native.nii.gz
${PHASE1_ANAT_STEP6_DIR}/subc20_labels.tsv
${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv
```

phase1 anat 可视化：

```text
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t1/atlas/z=*.png
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t1/subcortex/<ROI>/z=*.png
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t2/atlas/z=*.png
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t2/subcortex/<ROI>/z=*.png
```

### Stepview

```text
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step6-1_distal_native.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step6-2_sn_native.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step6-3_subc20_native.nii.gz
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step6-4_hybrid_atlas.nii.gz
```

### Atlas 定义

最终 Hybrid Atlas 固定为：

```text
68 cortical ROI + 20 subcortical ROI = 88 ROI
```

labels 顺序完全由：

```text
/data/bryang/project/CNS/pipeline/framework/details/roi.tsv
```

控制。

## step7_t1t2_myelin

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step7_t1t2_myelin.sh
```

### 输入

```text
${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz
/data/bryang/project/CNS/pipeline/framework/details/roi.tsv
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.white
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.white
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.pial
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.pial
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.sphere
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.sphere
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.sphere.reg
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.sphere.reg
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.thickness
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.thickness
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/lh.sulc
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/surf/rh.sulc
/data/bryang/project/CNS/tools/HCPpipelines-5.0.0/global/templates/standard_mesh_atlases/
```

### 输出

区域值与体素级 myelin：

```text
${PHASE1_ANAT_STEP7_DIR}/manifest.tsv
${PHASE1_ANAT_STEP7_DIR}/${SUBJECT_ID}_desc-t1t2_myelin_88.csv
${PHASE1_ANAT_STEP7_DIR}/${SUBJECT_ID}_desc-myelin_t1wdivt2w.nii.gz
```

native surface 中间产物：

```text
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.L.white.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.R.white.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.L.pial.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.R.pial.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.L.midthickness.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.R.midthickness.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.L.sphere.reg.reg_LR.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.R.sphere.reg.reg_LR.native.surf.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.L.T1w.native.func.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.R.T1w.native.func.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.L.T2w.native.func.gii
${PHASE1_ANAT_STEP7_DIR}/native/${SUBJECT_ID}.R.T2w.native.func.gii
```

32k fsLR 输出：

```text
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.L.midthickness.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.surf.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.R.midthickness.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.surf.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.L.inflated.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.surf.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.R.inflated.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.surf.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.L.T1w.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.func.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.R.T1w.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.func.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.L.T2w.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.func.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.R.T2w.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.func.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.L.Myelin.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.func.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.R.Myelin.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.func.gii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.T1w.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.dscalar.nii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.T2w.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.dscalar.nii
${PHASE1_ANAT_STEP7_DIR}/fsLR${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k/${SUBJECT_ID}.Myelin.${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fs_LR.dscalar.nii
```

可视化输出：

```text
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t1t2_myelin/t1w_${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fsLR.png
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t1t2_myelin/t2w_${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fsLR.png
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/t1t2_myelin/myelin_t1wdivt2w_${PHASE1_TISSUE_PROFILE_FSLR_MESH_K}k_fsLR.png
```

### Stepview

```text
${SUBJECT_WORK_ROOT}/visualization/phase1_anat/stepview/step7-1_myelin_t1wdivt2w.nii.gz
```

### 区域值 CSV 列顺序

```text
index
label
t1w
t2w
myelin
voxel_count
valid_myelin_voxel_count
```

其中前两列 `index` 和 `label` 直接复制自：

```text
/data/bryang/project/CNS/pipeline/framework/details/roi.tsv
```

并严格服从该文件顺序。

### 关键参数

```text
PHASE1_TISSUE_PROFILE_ENABLE
PHASE1_TISSUE_PROFILE_CIFTI_ENABLE
PHASE1_TISSUE_PROFILE_FSLR_MESH_K
PHASE1_TISSUE_PROFILE_HIGHRES_MESH_K
PHASE1_SURFACE_PLOT_ENV
PHASE1_SURFACE_PLOT_MRI_PYTHON
PHASE1_SURFACE_PLOT_OSMESA_PYTHON
```

### 关键工具与用途

```text
FreeSurfer mris_convert
  把 FreeSurfer surface/thickness/sulc 转成 GIFTI

Connectome Workbench wb_command -surface-average
  用 white 和 pial 生成 midthickness

Connectome Workbench wb_command -surface-sphere-project-unproject
  把 FreeSurfer sphere.reg 拼接到 fsLR 配准球面

Connectome Workbench wb_command -volume-to-surface-mapping
  把 T1/T2 映射到 native cortex surface

Connectome Workbench wb_command -metric-resample
  把 native surface metric 重采样到 32k fsLR

Connectome Workbench wb_command -cifti-create-dense-scalar
  组装 T1w/T2w/Myelin 的 dscalar

Python extract_t1t2_myelin_profiles.py
  从 88 ROI Hybrid Atlas 中提取区域平均值并生成体素级 myelin

Python plot_fslr_scalar_surfaces.py
  基于 surfplot / BrainSpace / PyVista / VTK 读取 32k fsLR metric，输出左右半球 lateral/medial 四视图 PNG

### 当前绘图执行逻辑

```text
PHASE1_SURFACE_PLOT_ENV=osmesa
  直接调用 PHASE1_SURFACE_PLOT_OSMESA_PYTHON

PHASE1_SURFACE_PLOT_ENV=mri_env
  优先用 xvfb-run -a 调用 PHASE1_SURFACE_PLOT_MRI_PYTHON
  若机器没有 xvfb-run，则直接调用 PHASE1_SURFACE_PLOT_MRI_PYTHON
```

## step8_eeg_leadfield

代码入口：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat/step8_eeg_leadfield.sh
```

### 输入

```text
${PHASE1_ANAT_STEP1_DIR}/t1_n4.nii.gz
${PHASE1_ANAT_STEP1_DIR}/t2_coreg_t1.nii.gz
${PHASE1_ANAT_STEP2_DIR}/aparc+aseg.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv
${PHASE1_ANAT_STEP2_DIR}/surfer_subjects/${SUBJECT_ID}/
${PHASE1_ANAT_STEP8_DIR}/simnibs/m2m_${SIMNIBS_SUBJECT_TAG}/eeg_positions/EEG10-10_UI_Jurak_2007.csv
${PHASE1_EEG_CUSTOM_CAP_CSV}
```

T2 相关输入只在 `PHASE1_EEG_USE_T2=1` 且 Step1 已生成 `t2_coreg_t1.nii.gz` 时送给 `charm`。

### 输出

```text
${PHASE1_ANAT_STEP8_DIR}/manifest.tsv
${PHASE1_ANAT_STEP8_DIR}/logs/charm.log
${PHASE1_ANAT_STEP8_DIR}/simnibs/m2m_${SIMNIBS_SUBJECT_TAG}/
${PHASE1_ANAT_STEP8_DIR}/simnibs/${SIMNIBS_SUBJECT_TAG}.msh
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/eeg_cap.csv
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/fem/*leadfield*.hdf5
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/${SUBJECT_ID}_EEG_Leadfield_${PHASE1_EEG_ELECTRODE_COUNT}x68.csv
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/${SUBJECT_ID}_EEG_Leadfield_${PHASE1_EEG_ELECTRODE_COUNT}x88.csv
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/${SUBJECT_ID}_EEG_Leadfield_qc.tsv
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/logs/prepare_cap.log
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/logs/prepare_tdcs_leadfield.log
${PHASE1_ANAT_STEP8_DIR}/leadfield/${PHASE1_EEG_ELECTRODE_COUNT}ch/${PHASE1_EEG_CAP_SOURCE}/logs/build_matrix.log
```

### 关键目录组织

Step8 结果按：

```text
leadfield/<电极数>ch/<传感器来源>/
```

做分层管理。

当前 `传感器来源` 允许：

```text
input
standard_10_10
standard_10_20
```

### 关键参数

```text
PHASE1_EEG_LEADFIELD_ENABLE
PHASE1_EEG_USE_T2
PHASE1_EEG_CHARM_USE_FS_DIR
PHASE1_EEG_CAP_SOURCE
PHASE1_EEG_CUSTOM_CAP_CSV
PHASE1_EEG_ELECTRODE_COUNT
PHASE1_EEG_REFERENCE_ELECTRODE
PHASE1_EEG_TDCS_SUBSAMPLING
PHASE1_EEG_LEADFIELD_FIELD
SIMNIBS_ENV_HOME
SIMNIBS_HOME
SIMNIBS_PYTHON
SIMNIBS_CHARM_CMD
SIMNIBS_PREPARE_TDCS_LEADFIELD_CMD
```

### 执行逻辑

1. 调用 `setup_tools_env` 建立 MRI/FSL/FreeSurfer 基础环境。
2. 若 Step8 被启用，再调用 `setup_simnibs_env`，把 SimNIBS 命令和 Python 注入当前 shell。
3. 以：

```text
SIMNIBS_SUBJECT_TAG="${SUBJECT_ID//-/_}_simnibs"
```

作为 SimNIBS 子项目名，在：

```text
${PHASE1_ANAT_STEP8_DIR}/simnibs/
```

下运行 `charm`。

4. `charm` 参数核心：

```text
charm <SIMNIBS_SUBJECT_TAG> <t1_n4> [t2_coreg_t1] [--fs-dir <surfer_subject_dir>]
```

5. 从：

```text
${SIMNIBS_M2M_DIR}/eeg_positions/EEG10-10_UI_Jurak_2007.csv
```

或外部自定义 cap CSV 中整理出当前 variant 的 `eeg_cap.csv`。

6. 调用：

```text
prepare_tdcs_leadfield <SIMNIBS_SUBJECT_TAG> <eeg_cap.csv> -o <fem_dir> [-s <subsampling>]
```

生成节点级 leadfield HDF5。

7. 用 `build_eeg_leadfield_matrix.py`：
   - 从 HDF5 中读取 ROI mesh 节点坐标和 `tdcs_leadfield`
   - 从 `aparc+aseg` 体积中为中灰质节点采样 Desikan 标签
   - 对 68 个皮层 ROI 做区域聚合
   - 按最终 88 ROI `labels.tsv` 顺序补全皮层下零列
   - 输出 `Nx68` / `Nx88` CSV 和 ROI 级 QC

### 68 / 88 维矩阵约定

- `Nx68`：
  - 行 = EEG 电极
  - 列 = 68 个 Desikan 皮层 ROI

- `Nx88`：
  - 行 = EEG 电极
  - 列 = 最终 Hybrid Atlas 的 88 ROI 顺序
  - 其中 20 个皮层下 ROI 当前直接补零

### 聚合规则

- 优先策略：对每个 Desikan 标签内落到中灰质 ROI mesh 的节点，求 normal-projected leadfield 的均值。
- 退化策略：若某个皮层 ROI 没采到任何节点，则用 `aparc+aseg` 中该标签的体素质心，在 ROI mesh 上取最近节点补一个代表值。
- 若 HDF5 中缺少可用三角面法向，则退化为向量模长均值，并在 QC 中写出 `reduction_mode=vector_magnitude`。

### Manifest 关键字段

```text
subject_id
status
simnibs_subject_tag
simnibs_root_dir
simnibs_m2m_dir
simnibs_head_mesh
leadfield_variant_dir
leadfield_cap_source
leadfield_cap_csv
leadfield_reference_electrode
leadfield_electrode_count
leadfield_field
leadfield_subsampling
leadfield_hdf5
leadfield_qc_tsv
leadfield_68_csv
leadfield_88_csv
leadfield_use_t2
custom_cap_csv
simnibs_python
simnibs_charm_cmd
simnibs_prepare_tdcs_leadfield_cmd
```

### 关键工具与用途

```text
SimNIBS charm
  基于 T1 和可选 T2 生成个体化 5 层头模与头皮 EEG 位置

SimNIBS prepare_tdcs_leadfield
  计算中灰质表面的节点级 TDCS leadfield

Python prepare_eeg_cap.py
  从自定义或标准 10-10 / 10-20 cap CSV 中整理当前变体的电极列表

Python build_eeg_leadfield_matrix.py
  把 SimNIBS HDF5 节点级 leadfield 聚合成 68 / 88 ROI CSV
```
```
