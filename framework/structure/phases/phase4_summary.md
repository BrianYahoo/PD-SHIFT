# phase4_summary - Summary and Reference Comparison

入口：

- `script/phases/phase4_summary.sh`

固定 step 顺序：

1. `step1_collect_outputs.sh`
2. `step2_export_tvp_model_inputs.sh`
3. `step3_compare_reference.sh`
4. `step4_write_report.sh`

## step1_collect_outputs

- 这个 step 汇总最终 atlas（分区模板）、FC（功能连接）和四类主 SC（结构连接），并为四类主 SC 输出 typed matrices（按脑区类别切开的矩阵）。

工具：

- Python `split_sc_matrices.py`
- Python / NumPy

## step2_export_tvp_model_inputs

- 这个 step 把 TVP（The Virtual Parkinsonian Patient，虚拟帕金森病人模型）需要的结构连接参考矩阵复制到 final 目录。

工具：

- Bash、文件复制

## step3_compare_reference

- 这个 step 把当前 subject 的 FC 和四类主 SC 分别与参考结果做对比并输出指标图。

工具：

- Python `compare_reference.py`

## step4_write_report

- 这个 step 写最终 markdown summary 和 phase4 manifest（阶段状态记录文件）。

工具：

- Bash
