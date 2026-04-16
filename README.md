# CNS MRI Pipeline

## Phase

1. `phase0_init` - Data Initialization
   - 功能：统一 HCP / Parkinson 原始输入，整理为后续统一读取的 BIDS 数据。
   - 输入：HCP raw 或 Parkinson raw。
   - 输出：`bids/sub-xxx/`，以及 `phases/phase0_init/` 下的标准化结果。

2. `phase1_anat` - Anatomical Reconstruction
   - 功能：完成个体解剖重建，并在原生空间生成 Hybrid Atlas。
   - 输入：`phase0_init` 的 T1 与 BIDS 结构数据。
   - 输出：`phases/phase1_anat/` 下的配准结果、逆向形变场与最终 atlas。

3. `phase2_fmri` - Functional Connectivity
   - 功能：完成 rs-fMRI 预处理并提取功能连接结果。
   - 输入：`phase0_init` 的 fMRI 数据与 `phase1_anat` 的个体 atlas。
   - 输出：`phases/phase2_fmri/` 下的 trial 结果、stepview 与 FC 相关产物。

4. `phase3_dwi` - Structural Connectivity
   - 功能：完成 DWI 预处理、纤维追踪与结构连接矩阵构建。
   - 输入：`phase0_init` 的 DWI 数据与 `phase1_anat` 的个体 atlas。
   - 输出：`phases/phase3_dwi/` 下的预处理结果、tractography 与 SC 矩阵。

5. `phase4_summary` - Summary and Reference Comparison
   - 功能：汇总最终产物并完成参考数据对比。
   - 输入：`phase1_anat`、`phase2_fmri`、`phase3_dwi` 的最终结果。
   - 输出：`phases/phase4_summary/` 下的 final、reports 与 comparison。

具体细节可参考 [framework](framework/)。
