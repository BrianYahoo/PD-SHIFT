# CNS MRI Pipeline Details

本层记录当前代码实际读写的主要路径。

## Raw Roots

HCP:

```text
/data/bryang/project/CNS/data/HCP/raw
```

Parkinson:

```text
/data/bryang/project/CNS/data/Parkinson/raw
```

## Workspace Roots

HCP:

```text
/data/bryang/project/CNS/data/HCP/workspace/<FreeSurfer|FastSurfer>/<subject>/
```

Parkinson:

```text
/data/bryang/project/CNS/data/Parkinson/workspace/<FreeSurfer|FastSurfer>/<subject>/
```

## Subject Tree

每个 subject 的当前标准目录：

```text
bids/sub-xxx/anat/
bids/sub-xxx/func/
bids/sub-xxx/dwi/
derivatives/cns-pipeline/sub-xxx/phases/phase0_init/
derivatives/cns-pipeline/sub-xxx/phases/phase1_anat/
derivatives/cns-pipeline/sub-xxx/phases/phase2_fmri/
derivatives/cns-pipeline/sub-xxx/phases/phase3_dwi/
derivatives/cns-pipeline/sub-xxx/phases/phase4_summary/
```

## Config-Driven Dataset Behavior

HCP 当前配置：

```text
DATASET_IMPORT_MODE=hcp_nifti
INIT_T1_RESAMPLE_ENABLE=0
INIT_T1_RESAMPLE_VOXEL_SIZE=1
PHASE1_BRAIN_EXTRACT_METHOD=bet
DEFAULT_FUNC_TR=0.72
FUNC_REQUIRE_JSON_TR=0
PHASE1_SURFER_HIRES=0
PHASE1_FASTSURFER_VOX_SIZE=min
FASTSURFER_USE_CUDA=0
```

Parkinson 当前配置：

```text
DATASET_IMPORT_MODE=parkinson_dicom
INIT_T1_RESAMPLE_ENABLE=1
INIT_T1_RESAMPLE_VOXEL_SIZE=0.7
PHASE1_BRAIN_EXTRACT_METHOD=synthstrip
FUNC_REQUIRE_JSON_TR=1
PHASE1_SURFER_HIRES=1
PHASE1_FREESURFER_NO_V8=1
PHASE1_FREESURFER_CORTEX_LABEL_ARGS=--no-fix-ga
PHASE1_FASTSURFER_LABEL_CORTEX_ARGS=--no-fix-ga --hip-amyg
PHASE1_FASTSURFER_VOX_SIZE=0.7
FASTSURFER_USE_CUDA=1
FASTSURFER_CUDA_AUTO_ASSIGN=1
FASTSURFER_CUDA_DEVICES=0,1,2,3,4,5,6,7
FASTSURFER_CUDA_SELECTION=least_memory
FASTSURFER_CUDA_MAX_SELECTED_DEVICES=5
```

## Logs

并行日志：

```text
/data/bryang/project/CNS/pipeline/logs/parallel/<dataset>/<FreeSurfer|FastSurfer>/<subject>.log
```

issue 相关日志：

```text
/data/bryang/project/CNS/pipeline/issues/log/
```

## Phase Documents

1. [phase0_init](./phases/phase0_init.md)
2. [phase1_anat](./phases/phase1_anat.md)
3. [phase2_fmri](./phases/phase2_fmri.md)
4. [phase3_dwi](./phases/phase3_dwi.md)
5. [phase4_summary](./phases/phase4_summary.md)
