# phase1_anat - Anatomical Reconstruction

入口：

- `script/phases/phase1_anat.sh`

固定 step 顺序：

1. `step1_brain_extract.sh`
2. `step2_surfer_recon.sh`
3. `step3_subcortical_syn.sh`
4. `step4_warpdrive_review.sh`
5. `step5_save_inverse_warp.sh`
6. `step6_distal_inverse_fusion.sh`
7. `step7_t1t2_myelin.sh`

## step1_brain_extract

- 这个 step 对 T1 做 N4（偏场校正，修正低频强度不均匀），生成脑掩膜，并在启用时把 T2 刚体配准到 T1。

工具：

- ANTs `N4BiasFieldCorrection`
- FSL `bet`、`fslmaths`、`flirt`
- FreeSurfer `mri_synthstrip`

## step2_surfer_recon

- 这个 step 用 FreeSurfer 或 FastSurfer 完成皮层与皮层下重建，并统一导出 native（个体原始）T1 空间的 `aparc+aseg`。

工具：

- FreeSurfer `recon-all`
- FastSurfer `run_fastsurfer.sh`
- FreeSurfer `mri_aparc2aseg`、`mri_convert`、`mri_vol2vol`

## step3_subcortical_syn

- 这个 step 用 `antsRegistration` 做 SyN（对称可微非线性配准）深部配准，把 MNI（标准模板空间）atlas（分区模板）对齐到个体 native 空间。

工具：

- ANTs `antsRegistration`
- FSL `fslmaths`
- Python atlas 组装脚本

## step4_warpdrive_review

- 这个 step 写配准复核占位结果，并按配置决定是否要求人工确认。

工具：

- Bash、manifest（阶段状态记录文件）

## step5_save_inverse_warp

- 这个 step 固化 Step3 的 affine（仿射矩阵）、forward warp（正向形变）和 inverse warp（反向形变），供后续 atlas 逆变换使用。

工具：

- Bash、文件复制

## step6_distal_inverse_fusion

- 这个 step 把深部 atlas 逆变换回 native T1，组装 20 个皮层下 ROI（感兴趣脑区），并与 Desikan（常用皮层分区方案）皮层分区合成为最终 88 ROI Hybrid Atlas。

工具：

- ANTs `antsApplyTransforms`
- Python `build_subcortical_atlas.py`
- Python `merge_custom_atlas.py`
- Python `visualize_hybrid_atlas_overlay.py`

## step7_t1t2_myelin

- 这个 step 按 88 ROI 顺序提取 T1w、T2w 和 myelin（T1w/T2w）区域值，并进一步生成 32k fsLR（标准皮层表面网格）CIFTI 与皮层 surf 图。

工具：

- FreeSurfer `mris_convert`
- Connectome Workbench `wb_command`
- Python `extract_t1t2_myelin_profiles.py`
- Python `plot_fslr_scalar_surfaces.py`
