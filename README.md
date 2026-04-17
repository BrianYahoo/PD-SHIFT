# PD-SHIFT 🧠
**Parkinson's Disease Subcortical-cortical Hybrid Imaging & Fusion Toolkit**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash%20%7C%20Python-green)](#)
[![Neuroimaging](https://img.shields.io/badge/Ecosystem-FreeSurfer%20%7C%20MRtrix3%20%7C%20ANTs%20%7C%20FSL-orange)](#)

**PD-SHIFT** is an advanced, high-fidelity neuroimaging preprocessing pipeline explicitly tailored for Parkinson's disease research. It bridges the anatomical gap between the highly folded cerebral cortex and crucial microscopic deep-brain targets via multi-spectral hybrid atlas fusion, providing a robust structural and functional connectome foundation for large-scale brain network modeling (e.g., digital twin brain simulations) and neuromodulation outcome prediction.

---

## ✨ Core Capabilities

* **Subcortical-Cortical Hybridization**: Seamlessly fuses standard cortical parcellations (FreeSurfer/FastSurfer) with ultra-high-resolution Lead-DBS atlases (e.g., DISTAL, Ewert), enabling millimeter-perfect targeting of the STN, GPi, and SN within a unified spatial framework.
* **Multi-Spectral Target Anchoring**: Leverages multi-channel `ANTs SyN` registration (T1w + T2w) combined with localized subcortical penalty masks, utilizing T2 iron deposition shadows to lock onto basal ganglia structures despite disease-related atrophy or ventricular enlargement.
* **Multimodal Functional Integration**: Implements a rigorous resting-state fMRI preprocessing framework, seamlessly projecting the hybridized high-precision atlas into functional space to extract clean BOLD signals and generate robust Functional Connectivity (FC) matrices.
* **Quantitative Connectomics**: Generates biologically meaningful, `SIFT2`-weighted structural connectomes coupled with inverse-node-volume scaling (`-scale_invnodevol`), outputting dimensionless probability density matrices perfectly optimized for differential equation-based dynamic network modeling.

---

## 🏗️ Pipeline Architecture

PD-SHIFT is engineered with a modular, highly fault-tolerant architecture designed for high-throughput GPU/CPU cluster environments. It consists of five distinct phases:

### Phase 0: Data Initialization (`phase0_init`)
* **Function:** Standardizes raw heterogeneous inputs into a unified framework.
* **Process:** Automatically detects, converts (via `dcm2niix`), and organizes raw DICOM (Parkinson cohort) or NIfTI (HCP cohort) datasets into strict **BIDS** (Brain Imaging Data Structure) compliance. Handles submillimeter (e.g., 0.7mm) isometric resampling dynamically.

### Phase 1: Anatomical Reconstruction (`phase1_anat`)
* **Function:** Individualized cortical surface reconstruction and highly precise deep-brain atlas fusion.
* **Process:**
  * Multi-contrast brain extraction (SynthStrip/BET) and N4 bias field correction.
  * High-resolution cortical reconstruction via FreeSurfer/FastSurfer with T2-pial refinement.
  * Dual-channel (T1+T2) ANTs SyN nonlinear registration anchored by native/MNI subcortical masks.
  * Generates the individualized **Hybrid Atlas** (Cortical + DISTAL + SN).

### Phase 2: Resting State fMRI Preprocessing (`phase2_fmri`)
* **Function:** Rigorous functional time-series extraction and cleanup.
* **Process:**
  * Slice-timing, susceptibility distortion correction (TOPUP), and rigid motion correction (MCFLIRT).
  * Boundary-Based Registration (BBR) to native anatomical space.
  * Covariate regression (GS/WM/CSF/HM), band-pass filtering, and FD-based scrubbing.
  * Outputs cleaned regional BOLD signals and Functional Connectivity (FC) matrices based on the Hybrid Atlas.

### Phase 3: dMRI Preprocessing & Tractography (`phase3_dwi`)
* **Function:** High-order fiber tracking and structural connectome generation.
* **Process:**
  * `MRtrix3` pre-processing: Denoising, Gibbs ringing removal, Eddy/Topup, and Bias correction.
  * Multi-Shell Multi-Tissue Constrained Spherical Deconvolution (MSMT-CSD) and tissue response normalization.
  * Anatomically-Constrained Tractography (ACT) with `iFOD2`, augmented by subcortical GM topological fixes to prevent premature streamline truncation at the STN/GPi.
  * `SIFT2` filtering and connectome assembly across multiple radial search parameters.
  * Outputs pure, dynamics-ready Structural Connectivity (SC) matrices.

### Phase 4: Summary & Quality Control (`phase4_summary`)
* **Function:** Automated pipeline auditing and visual verification.
* **Process:** Compiles manifest ledgers across all phases, cross-references matrix integrities, and generates multi-slice overlay PNGs for rapid visual inspection of the Hybrid Atlas mapping and target engagement.

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
* [**FreeSurfer**](https://surfer.nmr.mgh.harvard.edu/) (v7.0+) & [**FastSurfer**](https://github.com/Deep-MI/FastSurfer)
* [**MRtrix3**](https://www.mrtrix.org/) (v3.0+)
* [**ANTs**](https://github.com/ANTsX/ANTs) (Advanced Normalization Tools)
* [**dcm2niix**](https://github.com/rordenlab/dcm2niix) (For DICOM to NIfTI conversion)

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

  * `MNI152NLin2009bAsym` templates (T1w, T2w, and subcortical mask).
  * High-resolution subcortical atlases (e.g., DISTAL, SN) mapped to the same MNI 2009b space.

### 5. Configuration

Before running, you must specify your local paths and hardware configurations.

1.  Clone the repository:
    ```bash
    git clone https://github.com/BrianYahoo/PD-SHIFT.git
    cd PD-SHIFT
    ```
2.  Configure your environment variables and tool paths in `config/pipeline.env` and the dataset-specific files under `config/datasets/`.
3.  Ensure the FreeSurfer license is correctly exported:
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
