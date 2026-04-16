# phase3_dwi - Structural Connectivity

入口：

- `script/phases/phase3_dwi.sh`

固定 step 顺序：

1. `step1_import_raw.sh`
2. `step2_preprocess.sh`
3. `step3_fod.sh`
4. `step4_registration.sh`
5. `step5_tractography.sh`
6. `step6_connectome.sh`

## step1_import_raw

- 这个 step 把标准化 DWI（扩散像）和梯度信息导入为 MRtrix 的 `.mif` 工作格式。

工具：

- MRtrix `mrconvert`

## step2_preprocess

- 这个 step 完成去噪、去 Gibbs、topup/eddy（畸变与运动校正）和 bias correction（偏场校正），并生成 mean b0。

工具：

- MRtrix `dwidenoise`、`mrdegibbs`、`dwifslpreproc`、`dwibiascorrect`
- FSL 后端

## step3_fod

- 这个 step 估计 FOD（Fiber Orientation Distribution，纤维方向分布）并完成三组织归一化。

工具：

- MRtrix `dwi2response`
- MRtrix `dwi2fod`
- MRtrix `mtnormalise`

## step4_registration

- 这个 step 把 T1、atlas（分区模板）和 `aparc+aseg` 配准到 DWI，并生成 5TT（五组织类型图）和 GMWMI（灰白质交界种子）。

工具：

- FSL `flirt`
- MRtrix `5ttgen`、`5tt2gmwmi`、`mrconvert`、`mrcalc`
- Python `repair_5tt_hybrid_subcgm.py`
- Python `visualize_registration_overlay.py`

## step5_tractography

- 这个 step 基于 ACT（Anatomically Constrained Tractography，解剖约束纤维追踪）生成 tractography（纤维轨迹），并计算 SIFT2（纤维密度重标定权重）。

工具：

- MRtrix `tckgen`
- MRtrix `tcksift2`

## step6_connectome

- 这个 step 生成 `count`、`count_invnodevol`、`sift2`、`sift2_invnodevol` 四类 connectome，并额外输出 radial4 对照和 compare 图。

工具：

- MRtrix `tck2connectome`
- Python `compare_connectome_radial.py`
