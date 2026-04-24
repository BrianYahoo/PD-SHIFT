# phase4_summary

代码入口：

```text
/data/bryang/project/pipeline/script/phases/phase4_summary.sh
/data/bryang/project/pipeline/script/phases/phase4_summary/step*.sh
```

summary 目录：

```text
${PHASE4_SUMMARY_DIR}/
${FINAL_DIR}/
${REPORTS_DIR}/
${COMPARE_DIR}/
```

## step1_collect_outputs

### 输入

```text
${ATLAS_DIR}/${SUBJECT_ID}_desc-custom_dseg.nii.gz
${ATLAS_DIR}/${SUBJECT_ID}_labels.tsv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv
${PHASE3_DWI_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv
${PHASE2_FMRI_DIR}/${trial_name}/${SUBJECT_ID}_${trial_name}_FC_pearson.csv
${PHASE2_FMRI_DIR}/${trial_name}/${SUBJECT_ID}_${trial_name}_FC_fisherz.csv
${PHASE2_FMRI_DIR}/${trial_name}/stepresult/step5_bbr_fc_pearson.csv
${PHASE2_FMRI_DIR}/${trial_name}/stepresult/step5_bbr_fc_fisherz.csv
${PHASE2_FMRI_DIR}/${trial_name}/${SUBJECT_ID}_${trial_name}_FC_timeseries.tsv
${PHASE2_FMRI_DIR}/${trial_name}/${SUBJECT_ID}_${trial_name}_FC_qc.json
${PHASE2_FMRI_DIR}/${trial_name}/${SUBJECT_ID}_${trial_name}_FD_power.txt
${PHASE2_FMRI_DIR}/${trial_name}/${SUBJECT_ID}_${trial_name}_scrub_mask.txt
```

### 输出

atlas：

```text
${FINAL_DIR}/atlas/${SUBJECT_ID}_desc-custom_dseg.nii.gz
${FINAL_DIR}/${SUBJECT_ID}_labels.tsv
```

fMRI trial 汇总：

```text
${FINAL_DIR}/func/fmri_trials.tsv
${FINAL_DIR}/func/fc/${SUBJECT_ID}_${trial_name}_FC_pearson.csv
${FINAL_DIR}/func/fc/${SUBJECT_ID}_${trial_name}_FC_fisherz.csv
${FINAL_DIR}/func/fc/${SUBJECT_ID}_${trial_name}_FC_qc.json
${FINAL_DIR}/func/fc/${SUBJECT_ID}_${trial_name}_FD_power.txt
${FINAL_DIR}/func/fc/${SUBJECT_ID}_${trial_name}_scrub_mask.txt
${FINAL_DIR}/func/fc_bbr/${SUBJECT_ID}_${trial_name}_step5_bbr_fc_pearson.csv
${FINAL_DIR}/func/fc_bbr/${SUBJECT_ID}_${trial_name}_step5_bbr_fc_fisherz.csv
${FINAL_DIR}/func/timeseries/${SUBJECT_ID}_${trial_name}_FC_timeseries.tsv
${REPORTS_DIR}/fmri_trials_qc.json
```

trial 平均 FC：

```text
${FINAL_DIR}/${SUBJECT_ID}_FC_pearson.csv
${FINAL_DIR}/${SUBJECT_ID}_FC_fisherz.csv
${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_pearson.csv
${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_fisherz.csv
```

SC 复制：

```text
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_radial4.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_radial4.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_radial4.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_radial4.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_invnodevol_radial4.csv
```

typed SC：

```text
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_whole_brain.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_invnodevol_whole_brain.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_cortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_invnodevol_cortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_subcortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_invnodevol_subcortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_subcortex_cortex.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_count_invnodevol_subcortex_cortex.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_whole_brain.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_whole_brain.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_cortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_cortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_subcortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_subcortical.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_subcortex_cortex.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol_subcortex_cortex.csv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_typed_manifest.tsv
${FINAL_DIR}/dwi/sc/${SUBJECT_ID}_DTI_connectome_typed_qc.json
```

step1 manifest：

```text
${REPORTS_DIR}/step1_collect_outputs_manifest.tsv
```

## step2_export_tvp_model_inputs

### 输入

```text
${SC_REFERENCE_ROOT}/conn_excitator.npy
${SC_REFERENCE_ROOT}/conn_dopamine.npy
${SC_REFERENCE_ROOT}/conn_inhibitor.npy
```

### 输出

```text
${FINAL_DIR}/modeling/tvp/conn_excitator.npy
${FINAL_DIR}/modeling/tvp/conn_dopamine.npy
${FINAL_DIR}/modeling/tvp/conn_inhibitor.npy
${REPORTS_DIR}/step2_export_tvp_model_inputs_manifest.tsv
```

## step3_compare_reference

### 输入

```text
${FINAL_DIR}/${SUBJECT_ID}_labels.tsv
${FINAL_DIR}/${SUBJECT_ID}_FC_pearson.csv
${FINAL_DIR}/${SUBJECT_ID}_FC_bbr_pearson.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv
${FINAL_DIR}/func/fmri_trials.tsv
${FC_REFERENCE_ROOT}（默认：`/data/bryang/project/download/data/ssh/preprocessed`）
${SC_REFERENCE_ROOT}
```

### 输出

```text
${COMPARE_DIR}/summary_metrics.csv
${COMPARE_DIR}/summary_metrics.json
${COMPARE_DIR}/summary.md
${COMPARE_DIR}/fc/*.png
${COMPARE_DIR}/sc/sift2/log1p/*.png
${COMPARE_DIR}/sc/sift2_invnodevol/log1p/*.png
${COMPARE_DIR}/sc/sift2/max1/*.png
${COMPARE_DIR}/sc/sift2_invnodevol/max1/*.png
${COMPARE_DIR}/sc/count/log1p/*.png
${COMPARE_DIR}/sc/count_invnodevol/log1p/*.png
${COMPARE_DIR}/sc/count/max1/*.png
${COMPARE_DIR}/sc/count_invnodevol/max1/*.png
```

### 参考规则

HCP FC：

```text
${FC_REFERENCE_ROOT}/<subject>/<trial_name>/cortical/fc.npy
${FC_REFERENCE_ROOT}/<subject>/average/cortical/fc.npy
```

Parkinson FC：

```text
${FC_REFERENCE_ROOT}/Atlas_MSMAll/group/fc.npy
```

SC：

```text
conn_excitator.npy + conn_inhibitor.npy + conn_dopamine.npy
```

compare 脚本内部会把该 SC 参考对称化后再比较。

## step4_write_report

### 输入

```text
${FINAL_DIR}/atlas/${SUBJECT_ID}_desc-custom_dseg.nii.gz
${FINAL_DIR}/${SUBJECT_ID}_FC_pearson.csv
${FINAL_DIR}/${SUBJECT_ID}_FC_fisherz.csv
${FINAL_DIR}/func/fmri_trials.tsv
${REPORTS_DIR}/fmri_trials_qc.json
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_sift2_invnodevol.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count.csv
${FINAL_DIR}/${SUBJECT_ID}_DTI_connectome_count_invnodevol.csv
${FINAL_DIR}/modeling/tvp/conn_excitator.npy
${FINAL_DIR}/modeling/tvp/conn_dopamine.npy
${FINAL_DIR}/modeling/tvp/conn_inhibitor.npy
${COMPARE_DIR}/summary.md
```

### 输出

```text
${REPORTS_DIR}/phase4_summary.md
${REPORTS_DIR}/manifest.tsv
```
