# Structure

本层只讲当前代码框架怎么组织，不展开实现细节。

本层重点：

- pipeline 从哪里进入
- phase 按什么顺序执行
- 每个 step 用一句话负责什么
- 专业术语在第一次出现时给出简短解释

本层不写：

- 具体输入输出路径
- manifest（阶段状态记录文件）字段
- 参数细节
- 兼容逻辑

入口文档：

- [pipeline](./pipeline.md)
- [phase0_init](./phases/phase0_init.md)
- [phase1_anat](./phases/phase1_anat.md)
- [phase2_fmri](./phases/phase2_fmri.md)
- [phase3_dwi](./phases/phase3_dwi.md)
- [phase4_summary](./phases/phase4_summary.md)
