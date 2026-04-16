# CNS MRI Pipeline Structure

本层描述当前 pipeline 的执行结构。

1. [总体结构](./pipeline.md)
2. [phase0_init](./phases/phase0_init.md)
3. [phase1_anat](./phases/phase1_anat.md)
4. [phase2_fmri](./phases/phase2_fmri.md)
5. [phase3_dwi](./phases/phase3_dwi.md)
6. [phase4_summary](./phases/phase4_summary.md)

当前固定 phase 顺序：

1. `phase0_init`
2. `phase1_anat`
3. `phase2_fmri`
4. `phase3_dwi`
5. `phase4_summary`

入口选择：

- `--dataset hcp|parkinson`
- `--surfer free|fast`
- `--subject <subject_key>` 可选；不传则遍历 dataset raw 根目录下全部 subject。
