# 总体结构

## 入口

单进程入口：

```bash
bash /data/bryang/project/CNS/pipeline/script/process.sh --dataset hcp --surfer free --subject 100610
bash /data/bryang/project/CNS/pipeline/script/process.sh --dataset parkinson --surfer fast --subject 001
```

并行入口：

```bash
bash /data/bryang/project/CNS/pipeline/script/run/FreeH.sh
bash /data/bryang/project/CNS/pipeline/script/run/FastH.sh
bash /data/bryang/project/CNS/pipeline/script/run/FreeP.sh
bash /data/bryang/project/CNS/pipeline/script/run/FastP.sh
```

`parallel.sh` 默认 `MAX_PARALLEL=5`，可通过环境变量覆盖。

## 配置来源

全局默认值在：

- `/data/bryang/project/CNS/pipeline/config/pipeline.env`

dataset 覆盖值在：

- `/data/bryang/project/CNS/pipeline/config/datasets/hcp.env`
- `/data/bryang/project/CNS/pipeline/config/datasets/parkinson.env`

当前 dataset 行为：

- HCP：`DATASET_IMPORT_MODE=hcp_nifti`，不重采样 T1，`DEFAULT_FUNC_TR=0.72` 作为 HCP minimal JSON fallback，`PHASE1_SURFER_HIRES=0`，FastSurfer 使用 CPU。
- Parkinson：`DATASET_IMPORT_MODE=parkinson_dicom`，`INIT_T1_RESAMPLE_ENABLE=1`，`INIT_T1_RESAMPLE_VOXEL_SIZE=0.7`，`FUNC_REQUIRE_JSON_TR=1`，TR 必须来自 dcm2niix JSON，`PHASE1_SURFER_HIRES=1`，FastSurfer 使用 CUDA，并从配置 GPU 中按显存占用排序选择前 5 张卡分配。

## Workspace

每个 subject 的输出根目录由 dataset 和 surfer 共同决定：

```text
/data/bryang/project/CNS/data/HCP/workspace/<FreeSurfer|FastSurfer>/<subject>/
/data/bryang/project/CNS/data/Parkinson/workspace/<FreeSurfer|FastSurfer>/<subject>/
```

每个 subject 下固定包含：

```text
bids/sub-xxx/
derivatives/cns-pipeline/sub-xxx/phases/phase0_init/
derivatives/cns-pipeline/sub-xxx/phases/phase1_anat/
derivatives/cns-pipeline/sub-xxx/phases/phase2_fmri/
derivatives/cns-pipeline/sub-xxx/phases/phase3_dwi/
derivatives/cns-pipeline/sub-xxx/phases/phase4_summary/
```

## Phase

1. `phase0_init`
   功能：按 dataset config 导入 raw，标准化 T1/fMRI/DWI，写 BIDS 和 trial 清单。

2. `phase1_anat`
   功能：脑提取、FreeSurfer/FastSurfer 重建、MNI 到 native 的皮层下配准、Hybrid Atlas 生成。

3. `phase2_fmri`
   功能：对每个可处理 REST trial 做 rs-fMRI 预处理、BBR、ROI timeseries 和 FC。

4. `phase3_dwi`
   功能：DWI 预处理、FOD、ACT tractography、SC connectome。

5. `phase4_summary`
   功能：汇总 atlas/FC/SC，导出 TVP 建模矩阵，做参考对比，写报告。

## 子文档

1. [phase0_init](./phases/phase0_init.md)
2. [phase1_anat](./phases/phase1_anat.md)
3. [phase2_fmri](./phases/phase2_fmri.md)
4. [phase3_dwi](./phases/phase3_dwi.md)
5. [phase4_summary](./phases/phase4_summary.md)
