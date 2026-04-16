# phase4_summary

代码入口：

```text
script/phases/phase4_summary.sh
script/phases/phase4_summary/step*.sh
```

summary 根目录：

```text
phases/phase4_summary/
```

主要子目录：

```text
final/
reports/
comparison/
```

## step1_collect_outputs

### 输入

- `phase1_anat/atlas/sub-xxx_desc-custom_dseg.nii.gz` from phase1 step6
- `phase1_anat/atlas/sub-xxx_labels.tsv` from phase1 step6
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_pearson.csv` from phase2 step11
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_fisherz.csv` from phase2 step11
- `phase2_fmri/{trial_name}/stepresult/step5_bbr_fc_pearson.csv` from phase2 step11 diagnostics
- `phase2_fmri/{trial_name}/stepresult/step5_bbr_fc_fisherz.csv` from phase2 step11 diagnostics
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_timeseries.tsv` from phase2 step11
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FC_qc.json` from phase2 step11
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_FD_power.txt` from phase2 step10
- `phase2_fmri/{trial_name}/sub-xxx_{trial_name}_scrub_mask.txt` from phase2 step10
- `phase3_dwi/sub-xxx_DTI_connectome_sift2.csv` from phase3 step6
- `phase3_dwi/sub-xxx_DTI_connectome_count.csv` from phase3 step6
- `phase3_dwi/sub-xxx_DTI_connectome_sift2_radial4.csv` from phase3 step6
- `phase3_dwi/sub-xxx_DTI_connectome_count_radial4.csv` from phase3 step6

### 输出

Atlas:

```text
phase4_summary/final/atlas/sub-xxx_desc-custom_dseg.nii.gz
phase4_summary/final/sub-xxx_labels.tsv
```

fMRI trial 汇总：

```text
phase4_summary/final/func/fmri_trials.tsv
phase4_summary/final/func/fc/sub-xxx_{trial_name}_FC_pearson.csv
phase4_summary/final/func/fc/sub-xxx_{trial_name}_FC_fisherz.csv
phase4_summary/final/func/fc/sub-xxx_{trial_name}_FC_qc.json
phase4_summary/final/func/fc/sub-xxx_{trial_name}_FD_power.txt
phase4_summary/final/func/fc/sub-xxx_{trial_name}_scrub_mask.txt
phase4_summary/final/func/fc_bbr/sub-xxx_{trial_name}_step5_bbr_fc_pearson.csv
phase4_summary/final/func/fc_bbr/sub-xxx_{trial_name}_step5_bbr_fc_fisherz.csv
phase4_summary/final/func/timeseries/sub-xxx_{trial_name}_FC_timeseries.tsv
phase4_summary/reports/fmri_trials_qc.json
```

fMRI average：

```text
phase4_summary/final/sub-xxx_FC_pearson.csv
phase4_summary/final/sub-xxx_FC_fisherz.csv
phase4_summary/final/sub-xxx_FC_bbr_pearson.csv
phase4_summary/final/sub-xxx_FC_bbr_fisherz.csv
```

SC 复制：

```text
phase4_summary/final/sub-xxx_DTI_connectome_sift2.csv
phase4_summary/final/sub-xxx_DTI_connectome_count.csv
phase4_summary/final/sub-xxx_DTI_connectome_sift2_radial4.csv
phase4_summary/final/sub-xxx_DTI_connectome_count_radial4.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_sift2.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_count.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_sift2_radial4.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_count_radial4.csv
```

typed SC：

```text
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_count_whole_brain.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_count_cortical.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_count_subcortical.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_count_subcortex_cortex.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_sift2_whole_brain.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_sift2_cortical.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_sift2_subcortical.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_sift2_subcortex_cortex.csv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_typed_manifest.tsv
phase4_summary/final/dwi/sc/sub-xxx_DTI_connectome_typed_qc.json
```

report manifest：

```text
phase4_summary/reports/step1_collect_outputs_manifest.tsv
```

## step2_export_tvp_model_inputs

### 输入

- `SC_REFERENCE_ROOT/conn_excitator.npy`
- `SC_REFERENCE_ROOT/conn_dopamine.npy`
- `SC_REFERENCE_ROOT/conn_inhibitor.npy`

### 输出

```text
phase4_summary/final/modeling/tvp/conn_excitator.npy
phase4_summary/final/modeling/tvp/conn_dopamine.npy
phase4_summary/final/modeling/tvp/conn_inhibitor.npy
phase4_summary/reports/step2_export_tvp_model_inputs_manifest.tsv
```

## step3_compare_reference

### 输入

- `phase4_summary/final/sub-xxx_labels.tsv` from phase4 step1
- `phase4_summary/final/sub-xxx_FC_pearson.csv` from phase4 step1
- `phase4_summary/final/sub-xxx_FC_bbr_pearson.csv` from phase4 step1
- `phase4_summary/final/sub-xxx_DTI_connectome_sift2.csv` from phase4 step1
- `phase4_summary/final/sub-xxx_DTI_connectome_count.csv` from phase4 step1
- `phase4_summary/final/func/fmri_trials.tsv` from phase4 step1
- `FC_REFERENCE_ROOT`
- `SC_REFERENCE_ROOT`

### 输出

```text
phase4_summary/comparison/summary_metrics.csv
phase4_summary/comparison/summary_metrics.json
phase4_summary/comparison/summary.md
phase4_summary/comparison/fc/*.png
phase4_summary/comparison/sc/sift2/log1p/*.png
phase4_summary/comparison/sc/sift2/max1/*.png
phase4_summary/comparison/sc/count/log1p/*.png
phase4_summary/comparison/sc/count/max1/*.png
```

### Reference 规则

HCP FC：

- 单 trial：`ref/HCP/preprocessed/Atlas_MSMAll/individual/<subject>/<trial_name>/cortical/fc.npy`
- average：`ref/HCP/preprocessed/Atlas_MSMAll/individual/<subject>/average/cortical/fc.npy`

Parkinson FC：

- group：`ref/HCP/preprocessed/Atlas_MSMAll/group/fc.npy`

SC：

- `conn_excitator.npy + conn_inhibitor.npy + conn_dopamine.npy`
- 对称化后作为 TVP reference。
- 当前 compare 代码绘制 whole brain、cortical、subcortical 三个 scale；typed SC 另在 step1 输出。

## step4_write_report

### 输入

- `phase4_summary/final/atlas/sub-xxx_desc-custom_dseg.nii.gz` from phase4 step1
- `phase4_summary/final/sub-xxx_FC_pearson.csv` from phase4 step1
- `phase4_summary/final/sub-xxx_FC_fisherz.csv` from phase4 step1
- `phase4_summary/final/func/fmri_trials.tsv` from phase4 step1
- `phase4_summary/reports/fmri_trials_qc.json` from phase4 step1
- `phase3_dwi/sub-xxx_DTI_connectome_sift2.csv` from phase3 step6
- `phase3_dwi/sub-xxx_DTI_connectome_count.csv` from phase3 step6
- `phase4_summary/final/modeling/tvp/conn_excitator.npy` from phase4 step2
- `phase4_summary/final/modeling/tvp/conn_dopamine.npy` from phase4 step2
- `phase4_summary/final/modeling/tvp/conn_inhibitor.npy` from phase4 step2
- `phase4_summary/comparison/summary.md` from phase4 step3

### 输出

```text
phase4_summary/reports/phase4_summary.md
phase4_summary/reports/manifest.tsv
```
