# CNS MRI Pipeline Framework

本目录记录当前 pipeline 的结构约定和磁盘产物约定。

当前实现以代码和 dataset config 为准：

- 主入口：`/data/bryang/project/CNS/pipeline/script/process.sh`
- 并行入口：`/data/bryang/project/CNS/pipeline/script/parallel.sh`
- run wrapper：`/data/bryang/project/CNS/pipeline/script/run/`
- 全局默认配置：`/data/bryang/project/CNS/pipeline/config/pipeline.env`
- dataset 覆盖配置：`/data/bryang/project/CNS/pipeline/config/datasets/*.env`

文档分为两层：

- [structure](./structure/README.md)：phase/step 职责、执行顺序、关键配置。
- [details](./details/pipeline.md)：每个 step 的输入、输出和磁盘路径。

命名约束：

- 解剖 phase 固定为 `phase1_anat`。
- Surfer 引擎固定用入口参数 `--surfer free|fast` 选择。
- workspace 按 `FreeSurfer` / `FastSurfer` 分流。
- dataset 相关行为尽量通过 `config/datasets/<dataset>.env` 控制，不在 phase 文档中写死旧分支逻辑。
