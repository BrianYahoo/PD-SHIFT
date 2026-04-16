# phase1_anat

入口脚本：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase1_anat.sh
```

固定 step 顺序：

1. `step1_brain_extract.sh`
2. `step2_surfer_recon.sh`
3. `step3_subcortical_syn.sh`
4. `step4_warpdrive_review.sh`
5. `step5_save_inverse_warp.sh`
6. `step6_distal_inverse_fusion.sh`

## step1 Brain Extract

功能：

- 读取 phase0 标准化 T1。
- 执行 N4 bias correction。
- 生成分析用 brain、brain mask。
- 生成 FreeSurfer 专用宽松 `xmask` 和 `t1_freesurfer_brain`。

关键 config：

- `PHASE1_BRAIN_EXTRACT_METHOD=bet|synthstrip|none`
- `PHASE1_BET_F=0.30`
- `PHASE1_FS_XMASK_DILATIONS=2`

当前 dataset 设置：

- HCP：`PHASE1_BRAIN_EXTRACT_METHOD=bet`
- Parkinson：`PHASE1_BRAIN_EXTRACT_METHOD=synthstrip`

断点检测会检查 step1 产物与当前 phase0 T1 的 shape/affine 是否一致；如果 phase0 因 0.7mm config 重新导入，旧 step1 结果会被删除重算。

## step2 Surfer Recon

功能：

- 按入口 `--surfer free|fast` 选择 FreeSurfer 或 FastSurfer。
- 统一输出 `aparc+aseg.nii.gz` 和 `surfer_subjects/sub-xxx/`。
- 输出空间强制对齐到 `phase1_anat/step1_brain_extract/t1_n4.nii.gz`。

FreeSurfer 路径：

- 输入为 `t1_n4.nii.gz`。
- 命令核心为 `recon-all -all -noskullstrip -xmask <t1_freesurfer_xmask> -openmp <NTHREADS>`。
- `PHASE1_SURFER_HIRES=1` 时追加 `-hires`。
- `PHASE1_FREESURFER_NO_V8=1` 时追加 `-no-v8`。
- `PHASE1_FREESURFER_CORTEX_LABEL_ARGS` 非空时写 `recon-all.expert.opts`。
- 如果外置 skullstrip 路径第一次失败且日志出现缺 `brainmask.mgz`，脚本会把 `t1_freesurfer_brain` 对齐到 `orig.mgz`，写出 `brainmask.auto.mgz` 和 `brainmask.mgz` 后续跑一次。

FastSurfer 路径：

- full run 输入优先使用 BIDS T1。
- 命令核心为 `run_fastsurfer.sh --sid --sd --t1 --threads --device --viewagg_device --parallel --py`。
- segmentation 已存在但 surface 不完整时，进入 `--surf_only --edits` 续跑。
- `PHASE1_FASTSURFER_VOX_SIZE` 非 `min` 时追加 `--vox_size`。
- `PHASE1_SURFER_HIRES=1` 时导出 `CNS_FASTSURFER_FORCE_HIRES=1`，使 FastSurfer 内部 `recon-surf.sh` 的 recon-all 命令带 `-hires`。
- `PHASE1_FASTSURFER_LABEL_CORTEX_ARGS` 会传给定制的 FastSurfer label-cortex 路径；Parkinson 当前为 `--no-fix-ga --hip-amyg`。

当前 dataset 设置：

- HCP：`PHASE1_SURFER_HIRES=0`，`PHASE1_FASTSURFER_VOX_SIZE=min`，FastSurfer CPU。
- Parkinson：`PHASE1_SURFER_HIRES=1`，`PHASE1_FASTSURFER_VOX_SIZE=0.7`，FastSurfer CUDA。

配置刷新：

- step2 manifest 记录 `surfer_hires`、`fastsurfer_vox_size`、`t1_resample_voxel_size_mm`。
- 当前 config 与 manifest 不一致时，会清除旧 `surfer_subjects/sub-xxx` 并重建。
- 旧 subject 目录存在但缺 manifest 时，在启用 hires、T1 resample 或 FastSurfer 固定 vox size 的配置下也会清除重建。

## step3 Subcortical SyN

功能：

- 将 MNI2009b brain、DISTAL 6 ROI atlas、SN 2 ROI atlas准备到 step 目录。
- 使用 `antsRegistrationSyN.sh` 将 MNI2009b brain 配准到 native `t1_brain.nii.gz`。
- 输出 forward warp、inverse warp 和 affine。

关键 config：

- `PHASE1_REG_TRANSFORM=s`
- `PHASE1_LEADDBS_PRESET` 记录深部核团优先配准策略说明。

## step4 WarpDrive Review

功能：

- 写出人工复核说明。
- `WARPDRIVE_REVIEW_REQUIRED=0` 时写 `warpdrive_review.skipped` 并继续。
- `WARPDRIVE_REVIEW_REQUIRED=1` 时要求存在 `warpdrive_review.ok`。

## step5 Save Inverse Warp

功能：

- 将 step3 的 affine、forward warp、inverse warp 复制到稳定路径。
- 后续 atlas inverse fusion 只读取 step5 的保存结果。

## step6 Distal Inverse Fusion

功能：

- 用 step5 warp 将 DISTAL 和 SN atlas 逆变换到 native T1 空间。
- 用 `build_subcortical_atlas.py` 生成固定 20 ROI 皮层下图谱。
- 用 `merge_custom_atlas.py` 将 68 个 Desikan 皮层 ROI 与 20 个皮层下 ROI 合并为 88 ROI Hybrid Atlas。
- 用 `visualize_hybrid_atlas_overlay.py` 输出 atlas 全脑叠加和 subcortex 分 ROI 可视化。

最终 atlas：

- 68 个皮层 ROI，source 为 `desikan`。
- 20 个皮层下 ROI，source 为 `subcortical`。
- labels 顺序由 `framework/details/roi.tsv` 固定。
