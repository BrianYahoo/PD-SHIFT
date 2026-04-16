# CNS Lab MRI Pipeline

## Phase

0. Data Initialization - `phase0_init`
   - 功能：统一 HCP / Parkinson 原始输入，整理为后续统一读取的 BIDS 数据。
   - 输入：HCP raw 或 Parkinson raw。
   - 输出：BIDS 标准格式数据。

1. Anatomical Reconstruction - `phase1_anat`
   - 功能：完成个体解剖重建，并在原生空间生成 Hybrid Atlas。
   - 输入：T1 与 T2 结构像数据。
   - 输出：配准过程、逆向形变场以及配准后的脑区划分。

2. Resting State fMRI Preprocessing - `phase2_fmri`
   - 功能：完成 rs-fMRI 预处理并提取功能连接结果。
   - 输入：静息态 fMRI 数据与Phase1配准得到的脑区划分。
   - 输出：各脑区 BOLD 信号与功能连接 FC 矩阵。

3. DWI Preprocessing - `phase3_dwi`
   - 功能：完成 DWI 预处理、纤维追踪与结构连接矩阵构建。
   - 输入：DWI 数据与Phase1配准得到的脑区划分。
   - 输出：结构连接 SC 矩阵。

4. Summary and Reference Comparison - `phase4_summary`
   - 功能：汇总最终产物并完成参考数据对比。

具体细节可参考 [framework](framework/)。
