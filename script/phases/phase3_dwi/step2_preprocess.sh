#!/usr/bin/env bash
set -euo pipefail

# 计算当前 step 脚本所在目录，后面要回到 script 根目录加载公共函数。
STEP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${STEP_DIR}/../../common.sh"

# 加载当前 dataset 和 subject 的配置。
load_config
# 加载 conda、FSL、FreeSurfer、ANTs 等工具环境。
setup_tools_env

# 检查当前 step 依赖的命令是否存在。
require_cmd "$PYTHON_BIN"
require_cmd dwidenoise
require_cmd mrdegibbs
require_cmd dwifslpreproc
require_cmd dwibiascorrect
require_cmd dwi2mask
require_cmd dwiextract
require_cmd mrmath
require_cmd mrcat
require_cmd mrconvert
require_cmd mrinfo

# 如果 DWI 预处理主结果和导出结果已存在，则直接跳过。
if [[ -f "${DWI_DIR}/dwi_preproc_bias.mif" && -f "${DWI_DIR}/dwi_mask.mif" && -f "${DWI_DIR}/mean_b0.nii.gz" && -f "${DWI_DIR}/data.nii.gz" && -f "${DWI_DIR}/data.bvec" && -f "${DWI_DIR}/data.bval" && -f "${DWI_DIR}/brain_mask.nii.gz" ]]; then
  log "[phase3_dwi] Step2 already done for ${SUBJECT_ID}"
  exit 0
fi

# 如果去噪和 Gibbs 去伪影结果还不存在，则先完成这两步。
if [[ ! -f "${DWI_DIR}/dwi_den_gibbs.mif" ]]; then
  dwidenoise "${DWI_DIR}/dwi_raw.mif" "${DWI_DIR}/dwi_denoised.mif" -noise "${DWI_DIR}/noise.mif"
  mrdegibbs "${DWI_DIR}/dwi_denoised.mif" "${DWI_DIR}/dwi_den_gibbs.mif"
fi

# 如果预处理后的 DWI 还不存在，则执行 eddy/topup 流程。
if [[ ! -f "${DWI_DIR}/dwi_preproc.mif" ]]; then
  # 从 JSON 中读取相位编码方向。
  PE_DIR="$("$PYTHON_BIN" - "${INIT_STEP0_DIR}/dwi.json" <<'PY'
import json
import sys
print(json.load(open(sys.argv[1], "r", encoding="utf-8")).get("PhaseEncodingDirection", "i-"))
PY
)"
  # 统一定义传给 eddy 的参数。
  # 不显式传 --nthr，避免 GPU 版 eddy_cuda 因只接受 --nthr=1 而直接失败。
  # CPU 回退时改由 OpenMP 环境变量控制线程数。
  export OMP_NUM_THREADS="${NTHREADS}"
  EDDY_OPTS=" --slm=linear --repol --data_is_shelled "
  # 如果存在反向 DWI，则走成对反向相位编码预处理。
  if [[ -f "${DWI_DIR}/dwi_rev_raw.mif" ]]; then
    dwiextract "${DWI_DIR}/dwi_den_gibbs.mif" - -bzero | mrmath - mean "${DWI_DIR}/b0_main_mean.mif" -axis 3 -force
    dwiextract "${DWI_DIR}/dwi_rev_raw.mif" - -bzero | mrmath - mean "${DWI_DIR}/b0_rev_mean.mif" -axis 3 -force
    mrcat "${DWI_DIR}/b0_main_mean.mif" "${DWI_DIR}/b0_rev_mean.mif" -axis 3 "${DWI_DIR}/se_epi_pair.mif" -force
    dwifslpreproc "${DWI_DIR}/dwi_den_gibbs.mif" "${DWI_DIR}/dwi_preproc.mif" \
      -rpe_pair \
      -se_epi "${DWI_DIR}/se_epi_pair.mif" \
      -pe_dir "$PE_DIR" \
      -eddy_options "$EDDY_OPTS" \
      -scratch "${DWI_DIR}/scratch_dwifslpreproc" \
      -force
  # 如果不存在反向 DWI，则退回到无反向数据流程。
  else
    dwifslpreproc "${DWI_DIR}/dwi_den_gibbs.mif" "${DWI_DIR}/dwi_preproc.mif" \
      -rpe_none \
      -pe_dir "$PE_DIR" \
      -eddy_options "$EDDY_OPTS" \
      -scratch "${DWI_DIR}/scratch_dwifslpreproc" \
      -force
  fi
fi

# 如果 bias 校正结果还不存在，则执行 bias 校正并生成脑掩膜。
if [[ ! -f "${DWI_DIR}/dwi_preproc_bias.mif" ]]; then
  dwibiascorrect ants "${DWI_DIR}/dwi_preproc.mif" "${DWI_DIR}/dwi_preproc_bias.mif" -bias "${DWI_DIR}/dwi_bias.mif" -force
  dwi2mask "${DWI_DIR}/dwi_preproc_bias.mif" "${DWI_DIR}/dwi_mask.mif" -force
fi

# 如果平均 b0 图像还不存在，则导出 mean b0 到 nifti。
if [[ ! -f "${DWI_DIR}/mean_b0.nii.gz" ]]; then
  dwiextract "${DWI_DIR}/dwi_preproc_bias.mif" - -bzero | mrmath - mean "${DWI_DIR}/mean_b0.mif" -axis 3 -force
  mrconvert "${DWI_DIR}/mean_b0.mif" "${DWI_DIR}/mean_b0.nii.gz" -force
fi

# 如果 FSL 兼容版 DWI 文件还不存在，则导出 data.nii.gz、bvec、bval 和脑掩膜。
if [[ ! -f "${DWI_DIR}/data.nii.gz" ]]; then
  mrconvert "${DWI_DIR}/dwi_preproc_bias.mif" "${DWI_DIR}/data.nii.gz" -force
  mrinfo "${DWI_DIR}/dwi_preproc_bias.mif" -export_grad_fsl "${DWI_DIR}/data.bvec" "${DWI_DIR}/data.bval"
  mrconvert "${DWI_DIR}/dwi_mask.mif" "${DWI_DIR}/brain_mask.nii.gz" -datatype uint8 -force
fi
