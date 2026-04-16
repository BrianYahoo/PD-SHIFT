# phase3_dwi

入口脚本：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase3_dwi.sh
```

固定 step 顺序：

1. `step1_import_raw.sh`
2. `step2_preprocess.sh`
3. `step3_fod.sh`
4. `step4_registration.sh`
5. `step5_tractography.sh`
6. `step6_connectome.sh`

## step1 Import Raw

工具：MRtrix `mrconvert`

功能：

- 读取 phase0 标准化 DWI NIfTI、bval、bvec、JSON。
- 生成 `dwi_raw.mif`。
- 如果 `DWI_ENABLE_REVERSE_PE=1` 且 reverse PE 文件存在，生成 `dwi_rev_raw.mif`。

## step2 Preprocess

工具：MRtrix、FSL

功能：

- `dwidenoise` 去噪。
- `mrdegibbs` 去 Gibbs ringing。
- 使用 reverse PE 时执行 `dwifslpreproc` topup/eddy 路径。
- 执行 bias correction。
- 生成 DWI mask、mean b0、NIfTI/bval/bvec 导出。

## step3 FOD

工具：MRtrix

功能：

- 用 `dwi2response dhollander` 估计 WM、GM、CSF 响应函数。
- 用 `dwi2fod msmt_csd` 生成三组织 FOD。
- 用 `mtnormalise` 生成归一化 FOD。

关键 config：

- `DWI_LMAX=8`

## step4 Registration

工具：FSL、MRtrix、Python utils

功能：

- 将 T1 brain 6 DOF 配准到 DWI mean b0。
- 将 88 ROI atlas 投到 DWI 空间，生成 `atlas_in_dwi.nii.gz`。
- 将 `aparc+aseg` 投到 DWI 空间，生成 ACT 需要的 `5tt_dwi.mif`。
- 生成 `gmwmi_seed.mif`。
- 如果 `DWI_5TT_FIX_HYBRID_SUBCGM=1`，将 Hybrid Atlas 中 STN/GPi 等深部 ROI 对应区域强制修正到 5TT subcortical GM channel，避免 ACT 在深部靶点处截断。
- 输出 DWI registration 可视化到 `phase3_dwi/visualization/registration/`，并按 `atlas/` 与 `subcortex/` 子目录拆分。
- subcortex overlay 每个 ROI 只输出实际包含该 ROI 的 z 切片。

## step5 Tractography

工具：MRtrix

功能：

- 用 `tckgen` 执行 ACT 概率纤维追踪。
- 用 `tcksift2` 生成 SIFT2 权重。

关键 config：

- `STREAMLINES=5000000`
- `TRACT_MIN_LENGTH=4`
- `TRACT_MAX_LENGTH=200`
- `TRACT_MAX_ANGLE=45`

## step6 Connectome

工具：MRtrix、Python utils

功能：

- 用 `tck2connectome` 输出 88x88 SIFT2 connectome。
- 用 `tck2connectome` 输出 88x88 streamline count connectome。
- 主流程 assignment radius 来自 `CONNECTOME_ASSIGNMENT_RADIAL_SEARCH`，当前默认 2。
- 额外输出 radial 4 的 SIFT2/count 对比矩阵。
- 用 `compare_connectome_radial.py` 输出 radial 2 vs radial 4 对比图。

关键 config：

- `CONNECTOME_ASSIGNMENT_RADIAL_SEARCH=2`
- `CONNECTOME_SCALE_INVNODEVOL=1`
