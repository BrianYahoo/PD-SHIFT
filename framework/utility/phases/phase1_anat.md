# phase1_anat

入口脚本：

- `script/phases/phase1_anat.sh`

固定 step：

1. `step1_brain_extract`
2. `step2_surfer_recon`
3. `step3_subcortical_syn`
4. `step4_warpdrive_review`
5. `step5_save_inverse_warp`
6. `step6_distal_inverse_fusion`
7. `step7_t1t2_myelin`

## step1_brain_extract

功能：

- 对标准化 T1 做 N4。
- 生成分析用 brain、brain mask。
- 生成更宽松的 FreeSurfer `xmask` 和 `t1_freesurfer_brain`。
- 当 T2 启用时，对 T2 做 N4，并刚体 6-DOF 配准到 native T1。

概念输入：

- 标准化 T1
- 可选标准化 T2

概念输出：

- `t1_n4`
- `t1_brain`
- `t1_brain_mask`
- `t1_freesurfer_xmask`
- `t1_freesurfer_brain`
- 可选 `t2_n4`
- 可选 `t2_coreg_t1`
- 可选 `t2_coreg_t1_brain`

关键参数：

- `PHASE1_BRAIN_EXTRACT_METHOD`
- `PHASE1_BET_F`
- `PHASE1_FS_XMASK_DILATIONS`
- `PHASE1_T2_COREG_ENABLE`

工具：

- ANTs `N4BiasFieldCorrection`
- FSL `bet`、`flirt`、`fslmaths`
- FreeSurfer `mri_synthstrip`

## step2_surfer_recon

功能：

- 用 FreeSurfer 或 FastSurfer 完成 segmentation + surfaces。
- 统一导出 native T1 空间下的 `aparc+aseg`。
- 自动识别不完整 subject，并在可恢复时续跑，不可恢复时重置重跑。

概念输入：

- `t1_n4`
- `t1_brain_mask`
- `t1_freesurfer_xmask`
- 可选 `t2_coreg_t1`

概念输出：

- `surfer_subjects/<subject>`
- native `aparc+aseg`
- 统一 manifest

关键参数：

- `PHASE1_SURFER_HIRES`
- `PHASE1_FREESURFER_NO_V8`
- `PHASE1_FREESURFER_CORTEX_LABEL_ARGS`
- `PHASE1_FASTSURFER_LABEL_CORTEX_ARGS`
- `PHASE1_FASTSURFER_VOX_SIZE`
- `PHASE1_T2_SURFER_ENABLE`

实现细节：

- FreeSurfer 会在输入体素小于 `1.0 mm` 时自动启用 `-hires`。
- FreeSurfer 在 T2 可用时追加 `-T2` 和 `-T2pial`。
- FastSurfer 在 T2 可用时追加 `--t2` 和 `--reg_mode none`。
- FastSurfer 若 segmentation 已存在但表面不完整，会走 `--surf_only --edits` 续跑。

工具：

- FreeSurfer `recon-all`
- FastSurfer `run_fastsurfer.sh`
- FreeSurfer `mri_aparc2aseg`、`mri_convert`、`mri_vol2vol`

## step3_subcortical_syn

功能：

- 准备 MNI T1、可选 MNI T2、DISTAL 6 ROI、SN 2 ROI。
- 用原生 `antsRegistration` 做 MNI 到 native 的深部核团优先配准。
- 可选启用 T1+T2 双通道。
- 可选启用 MNI + native 双侧皮层下 mask。
- 可选启用 Affine 阶段。

概念输入：

- native `t1_brain`
- 可选 native `t2_coreg_t1_brain`
- native `aparc+aseg`
- MNI 模板和 Lead-DBS atlas

概念输出：

- `distal6_mni`
- `sn2_mni`
- MNI 到 native 的 affine / warp / inverse warp

关键参数：

- `PHASE1_T2_MULTICHANNEL_REG_ENABLE`
- `PHASE1_SUBCORTICAL_MASK_ENABLE`
- `PHASE1_REG_AFFINE_ENABLE`
- `MNI_T2`
- `MNI_SUBCORTICAL_MASK`

当前默认：

- HCP：Affine 开，subcortical mask 关。
- Parkinson：Affine 关，T2 双通道开，subcortical mask 开。

工具：

- ANTs `antsRegistration`
- FSL `fslmaths`
- Python `create_label_atlas.py`

## step4_warpdrive_review

功能：

- 写 WarpDrive 复核说明。
- 根据 `WARPDRIVE_REVIEW_REQUIRED` 决定是否要求人工确认。

工具：

- Bash

## step5_save_inverse_warp

功能：

- 固化 Step3 配准变换，避免后续阶段直接依赖 Step3 的临时路径。

工具：

- Bash

## step6_distal_inverse_fusion

功能：

- 把 DISTAL 和 SN 逆变换到 native T1。
- 组装固定 20 ROI 皮层下 atlas。
- 将 68 个皮层 ROI 和 20 个皮层下 ROI 合成为 88 ROI Hybrid Atlas。
- 输出 phase1 anat 的 T1/T2 atlas 与 subcortex 可视化。

概念输入：

- native `aparc+aseg`
- native warp
- DISTAL / SN MNI atlas
- ROI 主表

概念输出：

- `distal6_native`
- `sn2_native`
- `subc20_native`
- 最终 88 ROI atlas
- phase1 anat 可视化

工具：

- ANTs `antsApplyTransforms`
- Python `build_subcortical_atlas.py`
- Python `merge_custom_atlas.py`
- Python `visualize_hybrid_atlas_overlay.py`

## step7_t1t2_myelin

功能：

- 按 `roi.tsv` 顺序提取 88 个脑区的 T1w、T2w 和 myelin（T1w/T2w）平均值。
- 在皮层表面上把 T1w、T2w 和 myelin 映射到 native surface，并重采样到 32k fsLR。
- 输出三张 32k fsLR CIFTI dense scalar，以及对应的皮层 surf 图。

概念输入：

- native `t1_n4`
- native `t2_coreg_t1`
- 88 ROI Hybrid Atlas
- FreeSurfer / FastSurfer 的 `white`、`pial`、`sphere`、`sphere.reg`、`thickness`、`sulc`
- HCP standard mesh atlas

概念输出：

- 88 ROI 区域值 CSV
- 体素级 myelin NIfTI
- 32k fsLR 的 T1w / T2w / Myelin CIFTI
- T1w / T2w / Myelin 皮层 surf 图

关键参数：

- `PHASE1_TISSUE_PROFILE_ENABLE`
- `PHASE1_TISSUE_PROFILE_CIFTI_ENABLE`
- `PHASE1_TISSUE_PROFILE_FSLR_MESH_K`
- `PHASE1_TISSUE_PROFILE_HIGHRES_MESH_K`
- `PHASE1_SURFACE_PLOT_ENV`
- `PHASE1_SURFACE_PLOT_MRI_PYTHON`
- `PHASE1_SURFACE_PLOT_OSMESA_PYTHON`

工具：

- FreeSurfer `mris_convert`
- Connectome Workbench `wb_command`
- Python `extract_t1t2_myelin_profiles.py`
- Python `plot_fslr_scalar_surfaces.py`（基于 `surfplot`、`BrainSpace`、`PyVista`、`VTK`）
