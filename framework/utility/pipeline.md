# Pipeline Utility

## 入口

单 subject 运行：

```bash
bash script/process.sh --dataset hcp --surfer free --subject 100610
bash script/process.sh --dataset parkinson --surfer fast --subject 001
```

批量并行：

```bash
bash script/run/FreeH.sh
bash script/run/FastH.sh
bash script/run/FreeP.sh
bash script/run/FastP.sh
```

并行数由 `parallel.sh` 的 `MAX_PARALLEL` 控制，当前默认值为 `5`。

## 配置模型

配置加载顺序固定为：

1. `config/pipeline.env`
2. `config/datasets/<dataset>.env`

当前代码中的 dataset 行为主要通过 config 控制：

- 原始导入模式
- T1 重采样开关和目标分辨率
- T2 导入与后续使用开关
- fMRI TR 是否必须来自 JSON
- Step1 脑提取方法
- Step2 Surfer 参数
- Step3 多通道、mask、Affine 开关
- FastSurfer 是否启用 CUDA 及 GPU 选择策略

## 当前 dataset 重点

HCP：

- 原始导入模式为现成 NIfTI。
- 默认不重采样 T1。
- FastSurfer 默认走 CPU。
- Step3 默认启用 Affine。

Parkinson：

- 原始导入模式为 DICOM。
- 默认重采样 T1 到 `0.7 mm`。
- 默认启用 T2 导入、T2 刚体配准、T2 辅助 Surfer、T1+T2 多通道 Step3。
- FreeSurfer 在亚毫米输入下自动启用 `-hires`。
- FastSurfer 默认启用 CUDA，并按显存占用最少的 GPU 优先分配。
- Step3 默认关闭 Affine，优先保护深部区域局部锁定。

## Phase 概览

1. `phase0_init`
   导入原始数据，统一成 pipeline 标准输入和 BIDS。

2. `phase1_anat`
   生成 native T1 空间下的表面、分割和 88 ROI Hybrid Atlas。

3. `phase2_fmri`
   对每个 REST trial 做时空预处理、BBR 和 FC 提取。

4. `phase3_dwi`
   做 DWI 预处理、ACT tractography 和 SC connectome。

5. `phase4_summary`
   汇总 atlas、FC、SC，导出建模矩阵并与参考结果对比。

## 子文档

- [phase0_init](./phases/phase0_init.md)
- [phase1_anat](./phases/phase1_anat.md)
- [phase2_fmri](./phases/phase2_fmri.md)
- [phase3_dwi](./phases/phase3_dwi.md)
- [phase4_summary](./phases/phase4_summary.md)
