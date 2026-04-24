# PD-SHIFT 🧠
**Parkinson's Disease Subcortical-cortical Hybrid Imaging & Fusion Toolkit**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash%20%7C%20Python-green)](#)
[![Neuroimaging](https://img.shields.io/badge/Ecosystem-FreeSurfer%20%7C%20MRtrix3%20%7C%20ANTs%20%7C%20FSL-orange)](#)

**PD-SHIFT** is a high-fidelity neuroimaging preprocessing pipeline for Parkinson's disease and HCP-style multimodal MRI. It bridges the anatomical gap between the highly folded cerebral cortex and crucial microscopic deep-brain targets via hybrid atlas fusion, providing a structural and functional connectome foundation for large-scale brain network modeling and neuromodulation outcome prediction.

---

## ✨ Core Capabilities

* **Subcortical-Cortical Hybridization**: Seamlessly fuses standard cortical parcellations (FreeSurfer/FastSurfer) with Lead-DBS atlases (e.g., DISTAL, ATAG/SN), enabling unified cortex-subcortex analyses in one native-space atlas.
* **Config-Driven Deep Registration**: Supports either native Lead-DBS normalization or the in-house ANTs-based fallback pathway, with optional T1w+T2w multi-contrast anchoring when the dataset configuration enables T2 input.
* **Multimodal Functional Integration**: Implements a rigorous resting-state fMRI preprocessing framework, seamlessly projecting the hybridized high-precision atlas into functional space to extract clean BOLD signals and generate robust Functional Connectivity (FC) matrices.
* **Quantitative Connectomics**: Generates four structural connectome variants per subject (`count`, `count+invnodevol`, `sift2`, `sift2+invnodevol`) together with typed whole/cortex/subcortex/subcortex-to-cortex summaries.
* **Individualized EEG Forward Modeling**: Supports subject-specific SimNIBS/CHARM head meshing and EEG leadfield aggregation, exporting cortex-only (`Nx68`) and Hybrid Atlas-aligned (`Nx88`) forward matrices that can be directly coupled to the same parcellation used by SC/FC.

---

## 🏗️ Pipeline Architecture

PD-SHIFT is engineered with a modular, highly fault-tolerant architecture designed for high-throughput GPU/CPU cluster environments. It consists of five distinct phases:

### Phase 0: Data Initialization (`phase0_init`)
* **Function:** Standardizes raw heterogeneous inputs into a unified framework.
* **Process:** Automatically detects, converts (via `dcm2niix`), and organizes raw DICOM (Parkinson cohort) or NIfTI (HCP cohort) datasets into a BIDS-like workspace layout. Dataset-specific import rules, T1 selection priorities, and optional T1 resampling are all controlled from `config/datasets/*.env`.

### Phase 1: Anatomical Reconstruction (`phase1_anat`)
* **Function:** Individualized cortical surface reconstruction and deep-brain atlas fusion.
* **Process:**
  * Multi-contrast brain extraction (SynthStrip/BET) and N4 bias field correction.
  * High-resolution cortical reconstruction via FreeSurfer/FastSurfer, with automatic `-hires` handling for submillimeter FreeSurfer inputs and optional T2-pial refinement when T2 is enabled.
  * Step 3 supports native Lead-DBS normalization or the in-house ANTs fallback, depending on `PHASE1_LEADDBS_NATIVE_ENABLE`.
  * Generates the individualized **Hybrid Atlas** (Cortical + DISTAL + SN).
  * Optionally generates T1/T2/myelin profiles and individualized **EEG Leadfield** matrices via SimNIBS (`Nx68` cortex, `Nx88` hybrid-order padded).

### Phase 2: Resting State fMRI Preprocessing (`phase2_fmri`)
* **Function:** Rigorous functional time-series extraction and cleanup.
* **Process:**
  * Slice-timing (automatically skipped when `TR <= 1.0 s`), susceptibility distortion correction (TOPUP), and rigid motion correction (MCFLIRT).
  * Boundary-Based Registration (BBR) to native anatomical space.
  * Covariate regression (GS/WM/CSF/HM), band-pass filtering, and FD-based scrubbing.
  * Outputs cleaned regional BOLD signals, per-step diagnostic signal/FC products, and final Functional Connectivity (FC) matrices based on the Hybrid Atlas.

### Phase 3: dMRI Preprocessing & Tractography (`phase3_dwi`)
* **Function:** High-order fiber tracking and structural connectome generation.
* **Process:**
  * `MRtrix3` pre-processing: Denoising, Gibbs ringing removal, Eddy/Topup, and Bias correction. HCP defaults can use `eddy_cuda` with automatic GPU assignment and lock-based collision avoidance.
  * Multi-Shell Multi-Tissue Constrained Spherical Deconvolution (MSMT-CSD) and tissue response normalization.
  * Anatomically-Constrained Tractography (ACT) with `iFOD2`, augmented by subcortical GM topological fixes to prevent premature streamline truncation at the STN/GPi.
  * `SIFT2` filtering and connectome assembly across multiple radial search parameters.
  * Outputs four SC matrix variants together with typed whole/cortex/subcortex/subcortex-to-cortex summaries.

### Phase 4: Summary & Quality Control (`phase4_summary`)
* **Function:** Automated pipeline auditing and visual verification.
* **Process:** Compiles manifest ledgers across all phases, summarizes FC/SC outputs, and generates visual QC products under each subject's top-level `visualization/` directory rather than inside `derivatives/`.

---

## 🛠️ Prerequisites & Installation

PD-SHIFT relies on a synergistic ecosystem of industry-standard neuroimaging tools. It is designed to run on Linux/HPC environments.

### 1. System Requirements
* **OS:** Linux (Ubuntu 20.04/22.04 or CentOS 7+)
* **Hardware:** Multi-core CPU, 32GB+ RAM. 
* **GPU (Highly Recommended):** NVIDIA GPU for FastSurfer and FSL `eddy_cuda`. *(Note: If using Ampere/Ada Lovelace architectures like A100/RTX 5090, ensure you are using the appropriately compiled version of `eddy_cuda` to prevent fallback to CPU).*

### 2. Core Dependencies
Ensure the following neuroimaging suites are installed and correctly added to your system `$PATH`:
* [**FSL**](https://fsl.fmrib.ox.ac.uk/fsl/fslwiki) (v6.0+)
* [**FreeSurfer**](https://surfer.nmr.mgh.harvard.edu/) (current code path expects v8.x behavior, including `-no-v8`) & [**FastSurfer**](https://github.com/Deep-MI/FastSurfer)
* [**MRtrix3**](https://www.mrtrix.org/) (v3.0+)
* [**ANTs**](https://github.com/ANTsX/ANTs) (Advanced Normalization Tools)
* [**dcm2niix**](https://github.com/rordenlab/dcm2niix) (For DICOM to NIfTI conversion)
* [**SimNIBS**](https://simnibs.github.io/simnibs/build/html/index.html) (For individualized EEG leadfield modeling)
* [**MATLAB**](https://www.mathworks.com/) + [**SPM12**](https://www.fil.ion.ucl.ac.uk/spm/software/spm12/) + [**Lead-DBS**](https://www.lead-dbs.org/) (For the native Lead-DBS normalization branch)

### 3. Python Environment
PD-SHIFT utilizes Python as the connective tissue for matrix operations and BIDS logic. We recommend using Conda:
```bash
conda create -n pdshift python=3.9
conda activate pdshift
pip install -r requirements/requirements.txt
```

For headless surface rendering, the current pipeline also supports a separate OSMesa-based renderer environment:
```bash
conda create -n pdshift-osmesa python=3.10
conda activate pdshift-osmesa
pip install -r requirements/requirements-osmesa.txt
```

The repository therefore separates Python dependencies into:

* `requirements/requirements.txt`: Main pipeline Python dependencies.
* `requirements/requirements-osmesa.txt`: Optional headless surface-rendering stack using `vtk-osmesa`.

### 4. Atlas & Templates

The pipeline leverages assets from [Lead-DBS](https://www.lead-dbs.org/). Ensure you have the following assets accessible in your tools directory:

  * `MNI152NLin2009bAsym` templates (T1w, T2w, and brain mask).
  * High-resolution subcortical atlases (e.g., DISTAL, SN / ATAG) mapped to the same MNI 2009b space.

### 5. Configuration

Before running, you must specify your local paths and hardware configurations.

1.  Clone the repository:
    ```bash
    git clone https://github.com/BrianYahoo/PD-SHIFT.git
    cd PD-SHIFT
    ```
2.  Configure your environment variables and tool paths in `config/pipeline.env` and the dataset-specific files under `config/datasets/`.
3.  Review dataset-level switches carefully. In the current defaults:
    * `hcp` enables T2 import, native Lead-DBS normalization, and `eddy_cuda` auto-assignment.
    * `parkinson` currently runs T1-only by default, keeps native Lead-DBS normalization enabled, and leaves DWI `eddy` on CPU unless you explicitly change the dataset config.
4.  Ensure the FreeSurfer license is correctly exported:
    ```bash
    export FS_LICENSE=/path/to/your/license.txt
    ```

-----

## 📖 Detailed Framework Documentation

For a deep dive into the mathematical decisions, bash array configurations, and execution step-views, please refer to the detailed structural breakdown in the [framework](framework/) directory.

---
## 👤 Author

- **Boran Yang**
- 🦦 **GitHub:** [@BrianYahoo](https://github.com/BrianYahoo)
- 📧 **Email:** bryangsjtu@gmail.com
- 🏛️ **Affiliation:** Lab of Computational Neuroscience, Institute of Natural Sciences, SJTU
