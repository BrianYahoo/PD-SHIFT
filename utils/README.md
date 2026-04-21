# Utils Directory

`utils/` 现在按 `phase -> step -> function` 组织，避免所有 Python 工具平铺在同一层。

当前结构：

- `phase1_anat/step3/`
  - `create_label_atlas.py`
- `phase1_anat/step6/`
  - `build_subcortical_atlas.py`
  - `merge_custom_atlas.py`
  - `visualize_hybrid_atlas_overlay.py`
- `phase1_anat/step7/`
  - `extract_t1t2_myelin_profiles.py`
  - `plot_fslr_scalar_surfaces.py`
- `phase1_anat/step8/`
  - `prepare_eeg_cap.py`
  - `build_eeg_leadfield_matrix.py`
- `phase1_anat/legacy/`
  - `merge_distal_hybrid_atlas.py`
- `phase2_fmri/shared/`
  - `fmri_utils.py`
- `phase2_fmri/step2/`
  - `fmri_slice_timing.py`
- `phase2_fmri/step4/`
  - `plot_motion_metrics.py`
- `phase2_fmri/step7/`
  - `fmri_temporal_detrend.py`
- `phase2_fmri/step8/`
  - `fmri_regress_covariates.py`
- `phase2_fmri/step9/`
  - `fmri_temporal_filter.py`
- `phase2_fmri/step10/`
  - `fmri_scrubbing.py`
- `phase2_fmri/step11/`
  - `fmri_extract_signal.py`
- `phase2_fmri/step12/`
  - `fmri_stepwise_diagnostics.py`
- `phase2_fmri/maintenance/`
  - `refresh_fmri_motion_and_scrub_outputs.py`
  - `refresh_motion_metric_plots.py`
- `phase2_fmri/legacy/`
  - `compute_fc_matrix.py`
- `phase3_dwi/step4/`
  - `repair_5tt_hybrid_subcgm.py`
- `phase3_dwi/step6/`
  - `compare_connectome_radial.py`
- `phase4_summary/step1/`
  - `split_sc_matrices.py`
- `phase4_summary/step3/`
  - `compare_reference.py`
- `shared/visualization/`
  - `visualize_registration_overlay.py`

规则：

- 直接服务某个 step 的脚本，放到对应 `phaseX/stepY/`
- 多个 fMRI step 共用的基础函数，放到 `phase2_fmri/shared/`
- 跨 phase 复用的可视化工具，放到 `shared/`
- 已不在主流程中直接调用、但仍保留作参考的脚本，放到 `legacy/`
- 只用于批量修补历史产物的脚本，放到 `maintenance/`
