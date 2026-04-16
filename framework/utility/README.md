# Utility

本层解释当前 pipeline 每个 phase 和 step 的功能设计。

它关注：

- 这个 step 在做什么
- 概念上的输入和输出是什么
- 关键参数有哪些
- 用了什么工具

它不展开：

- 真实磁盘路径
- 绝对目录结构
- 兼容 symlink 等实现细节

入口文档：

- [pipeline](./pipeline.md)
- [phase0_init](./phases/phase0_init.md)
- [phase1_anat](./phases/phase1_anat.md)
- [phase2_fmri](./phases/phase2_fmri.md)
- [phase3_dwi](./phases/phase3_dwi.md)
- [phase4_summary](./phases/phase4_summary.md)
