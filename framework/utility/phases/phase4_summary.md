# phase4_summary

入口脚本：

- `script/phases/phase4_summary.sh`

固定 step：

1. `step1_collect_outputs`
2. `step2_export_tvp_model_inputs`
3. `step3_compare_reference`
4. `step4_write_report`

## step1_collect_outputs

功能：

- 汇总 phase1 atlas、phase2 trial FC、phase3 SC。
- 计算 trial 平均 FC 和平均 BBR FC。
- 复制主流程 SC 和 radial4 对照 SC。
- 将四类主 SC 变体都切分为 typed matrices。

typed SC 当前固定输出：

- `whole_brain`
- `cortical`
- `subcortical`
- `subcortex_cortex`

权重类型固定输出：

- `count`
- `count_invnodevol`
- `sift2`
- `sift2_invnodevol`

工具：

- Python、NumPy
- Python `split_sc_matrices.py`

## step2_export_tvp_model_inputs

功能：

- 将 TVP 参考结构连接矩阵复制到当前 subject 的 final summary 目录。

工具：

- Bash

## step3_compare_reference

功能：

- 比较当前 subject 与 FC / SC 参考结果。
- HCP 使用 individual reference。
- Parkinson 使用 HCP group FC reference。
- SC 使用 TVP 参考矩阵的对称化结果。

工具：

- Python `compare_reference.py`

## step4_write_report

功能：

- 生成最终 markdown summary。
- 生成 phase4 manifest。

工具：

- Bash
