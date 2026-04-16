# phase4_summary

入口脚本：

```text
/data/bryang/project/CNS/pipeline/script/phases/phase4_summary.sh
```

固定 step 顺序：

1. `step1_collect_outputs.sh`
2. `step2_export_tvp_model_inputs.sh`
3. `step3_compare_reference.sh`
4. `step4_write_report.sh`

## step1 Collect Outputs

功能：

- 汇总 phase1 atlas、phase2 FC、phase3 SC 到 `phase4_summary/final/`。
- 对每个 fMRI trial 复制 FC、BBR FC、timeseries、QC、FD、scrub mask。
- 对所有 trial 的 FC 和 BBR FC 求平均。
- 复制 88x88 SIFT2/count SC 和 radial4 对比矩阵。
- 调用 `split_sc_matrices.py` 输出 typed SC 矩阵。

typed SC 当前输出两个权重类型：

- `count`
- `sift2`

typed SC 当前输出四个尺度：

- `whole_brain`：88x88
- `cortical`：68x68
- `subcortical`：20x20
- `subcortex_cortex`：20x68

## step2 Export TVP Model Inputs

功能：

- 从 `SC_REFERENCE_ROOT` 复制 TVP 参考矩阵到 final modeling 目录。
- 输出 `conn_excitator.npy`、`conn_dopamine.npy`、`conn_inhibitor.npy`。

## step3 Compare Reference

工具：`compare_reference.py`

功能：

- FC 对比使用 BBR FC 的 cortical 68x68 子矩阵。
- HCP subject 对比 individual trial reference 和 individual average reference。
- Parkinson subject 对比 HCP group FC reference。
- SC 对比使用 TVP 的 `conn_excitator + conn_inhibitor + conn_dopamine` 对称化参考。
- SC 对比覆盖 `sift2` 和 `count`，并分别输出 `log1p` 与 `max1` 变换下的 whole brain、cortical、subcortical 结果。

## step4 Write Report

功能：

- 写出 `reports/phase4_summary.md`。
- 写出 `reports/manifest.tsv`。
- 报告记录 atlas、FC、SC、TVP modeling、reference comparison 的关键路径。
