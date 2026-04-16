# Pipeline Structure

## 入口

单 subject 主入口：

- `script/process.sh`

批量并行入口：

- `script/parallel.sh`
- `script/run/FreeH.sh`
- `script/run/FastH.sh`
- `script/run/FreeP.sh`
- `script/run/FastP.sh`

配置入口：

- `config/pipeline.env`
- `config/datasets/hcp.env`
- `config/datasets/parkinson.env`

## 执行顺序

固定 phase 顺序：

1. `phase0_init` - Data Initialization
2. `phase1_anat` - Anatomical Reconstruction
3. `phase2_fmri` - Functional Connectivity
4. `phase3_dwi` - Structural Connectivity
5. `phase4_summary` - Summary and Reference Comparison

## 框架规则

- 入口先加载全局 config，再叠加 dataset config。
- workspace（每个 subject 的工作目录）由 dataset 和 `FreeSurfer` / `FastSurfer` 引擎共同决定。
- 大多数 step 都带断点检测，依赖 manifest（阶段状态记录文件）和关键产物是否完整。
- 所有可视化和 stepview 都统一写到 subject 根目录下的 `visualization/`。

## Dataset 驱动

当前 dataset 差异主要由 config 控制，包括：

- 原始导入模式
- T1（结构像）是否重采样
- 是否导入和使用 T2（补充结构对比像）
- 脑提取方法
- FreeSurfer / FastSurfer 参数
- Step3 是否启用多通道配准、深部 mask 和 Affine（仿射变换，允许整体缩放和剪切）
- FastSurfer 是否启用 CUDA（GPU 加速）

## Phase Index

- [phase0_init](./phases/phase0_init.md)
- [phase1_anat](./phases/phase1_anat.md)
- [phase2_fmri](./phases/phase2_fmri.md)
- [phase3_dwi](./phases/phase3_dwi.md)
- [phase4_summary](./phases/phase4_summary.md)
