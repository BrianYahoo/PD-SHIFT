# phase3_dwi

入口脚本：

- `script/phases/phase3_dwi.sh`

固定 step：

1. `step1_import_raw`
2. `step2_preprocess`
3. `step3_fod`
4. `step4_registration`
5. `step5_tractography`
6. `step6_connectome`

## step1_import_raw

功能：

- 把标准化 DWI 和梯度信息转换成 MRtrix `.mif`。
- 可选导入 reverse PE。

关键参数：

- `DWI_ENABLE_REVERSE_PE`

工具：

- MRtrix `mrconvert`

## step2_preprocess

功能：

- 去噪、去 Gibbs、topup/eddy、bias correction。
- 生成 mask 与 mean b0，并导出 NIfTI 供后续配准。

工具：

- MRtrix `dwidenoise`
- MRtrix `mrdegibbs`
- MRtrix `dwifslpreproc`
- MRtrix `dwibiascorrect`

## step3_fod

功能：

- 估计 WM/GM/CSF 响应函数。
- 生成三组织 FOD。
- 做 mtnormalise。

关键参数：

- `DWI_LMAX`

工具：

- MRtrix `dwi2response`
- MRtrix `dwi2fod`
- MRtrix `mtnormalise`

## step4_registration

功能：

- 把 T1 brain 刚体配准到 DWI mean b0。
- 把 88 ROI atlas 和 `aparc+aseg` 投到 DWI。
- 生成 5TT 和 GMWMI。
- 可选修补 hybrid atlas 的深部 subcortical GM 区域。
- 若 T2 可用，则同时生成 T2 in DWI 和第二套 registration overlay。

关键参数：

- `DWI_5TT_FIX_HYBRID_SUBCGM`

工具：

- FSL `flirt`
- MRtrix `mrcalc`、`5ttgen`、`5tt2gmwmi`、`mrconvert`
- Python `repair_5tt_hybrid_subcgm.py`
- Python `visualize_registration_overlay.py`

## step5_tractography

功能：

- 基于 ACT 进行概率追踪。
- 生成 SIFT2 权重。

关键参数：

- `STREAMLINES`
- `TRACT_MIN_LENGTH`
- `TRACT_MAX_LENGTH`
- `TRACT_MAX_ANGLE`

工具：

- MRtrix `tckgen`
- MRtrix `tcksift2`

## step6_connectome

功能：

- 生成 88x88 的四类主 connectome：
- `count`
- `count_invnodevol`
- `sift2`
- `sift2_invnodevol`
- 主流程采用当前 assignment radius。
- 额外固定生成 radial 4 对照矩阵，并同样保留未缩放与 invnodevol 两套。
- 输出未缩放和 invnodevol 两张 radial compare 图。

关键参数：

- `CONNECTOME_ASSIGNMENT_RADIAL_SEARCH`

工具：

- MRtrix `tck2connectome`
- Python `compare_connectome_radial.py`
