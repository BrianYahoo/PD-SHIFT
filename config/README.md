# Config 说明

本目录存放两类配置：

- `.env`：运行参数配置，由 `common.sh` 加载。
- `.tsv`：结构性清单配置，用于告诉脚本应该装配哪些 ROI。

`.env` 参数的中文注释已经直接写在各自文件里。  
本说明文档专门解释当前 `config/` 目录下的非 `.env` TSV 配置文件。

## TSV 配置总览

当前实际存在并被主流程读取的 TSV 只有两个：

- [distal_gpe_gpi_stn_6.tsv](/data/bryang/project/CNS/pipeline/config/distal_gpe_gpi_stn_6.tsv)
- [sn_2.tsv](/data/bryang/project/CNS/pipeline/config/sn_2.tsv)

它们都在 `phase1_anat/step3_subcortical_syn.sh` 中被读取，调用入口是：

```text
python utils/phase1_anat/step3/create_label_atlas.py --roi-list <tsv>
```

对应代码位置：

- `step3_subcortical_syn.sh` 读取这两个 TSV
- `utils/phase1_anat/step3/create_label_atlas.py` 解析 TSV，并按表中顺序组装整数标签图

## 通用格式

这两个 TSV 的表头完全一致：

```tsv
hemi	roi
```

字段含义：

- `hemi`：半球，当前只允许 `lh` 或 `rh`
- `roi`：ROI 名称，必须和 atlas 目录中的 mask 文件名一致，不带扩展名

举例：

```tsv
hemi	roi
lh	GPe
rh	GPe
```

表示脚本会去 atlas 目录下读取：

```text
<atlas_dir>/lh/GPe.nii.gz
<atlas_dir>/rh/GPe.nii.gz
```

## 顺序规则

这类 TSV 不是单纯的“列举有哪些 ROI”，还同时决定了输出标签图里的编号顺序。

`utils/phase1_anat/step3/create_label_atlas.py` 的实现规则是：

1. 按 TSV 从上到下逐行读取
2. 第一行 ROI 被赋值为 `index=1`
3. 第二行 ROI 被赋值为 `index=2`
4. 依次递增

这意味着：

- 如果你调换 TSV 行顺序，输出标签图中的整数标签编号也会一起改变
- 下游 `*_labels.tsv` 中的 `index` 顺序也会一起改变

所以：

- 如果只是想补注释或查看内容，不要改动行顺序
- 如果必须改动 ROI 顺序，要明确知道这会改变 Step3 输出的标签编号

## hemisphere 约束

`create_label_atlas.py` 在读入 mask 后，还会根据 `hemi` 再做一次半球侧限制：

- `lh` 只保留 x 轴小于 0 的体素
- `rh` 只保留 x 轴大于 0 的体素

这意味着即使 mask 本身跨中线，脚本也会按半球再次裁切。

因此：

- `hemi` 必须写对
- 不要把左侧 ROI 写成 `rh`
- 不要把右侧 ROI 写成 `lh`

## distal_gpe_gpi_stn_6.tsv

文件：

- [distal_gpe_gpi_stn_6.tsv](/data/bryang/project/CNS/pipeline/config/distal_gpe_gpi_stn_6.tsv)

当前内容：

```tsv
hemi	roi
lh	GPe
lh	GPi
lh	STN
rh	GPe
rh	GPi
rh	STN
```

作用：

- 告诉 Step3 从 Lead-DBS 的 DISTAL atlas 中提取 6 个深部靶点 ROI
- 这些 ROI 会先被组装成 `distal6_mni.nii.gz`
- 然后在 Step6 中逆变换到 native T1 空间，成为后续 20 ROI 皮层下 atlas 的一部分

这 6 个 ROI 是：

- 左 GPe
- 左 GPi
- 左 STN
- 右 GPe
- 右 GPi
- 右 STN

下游用途：

- `phase1_anat/step3_subcortical_syn.sh`
- `phase1_anat/step6_distal_inverse_fusion.sh`
- `utils/phase1_anat/step6/build_subcortical_atlas.py`

修改约束：

- `roi` 名称必须和 DISTAL atlas 目录中的 mask 文件名一致
- 如果删掉某一行，对应 ROI 就不会再进入 subcortical atlas
- 如果新增某一行，前提是 atlas 目录里真的有对应 mask 文件

## sn_2.tsv

文件：

- [sn_2.tsv](/data/bryang/project/CNS/pipeline/config/sn_2.tsv)

当前内容：

```tsv
hemi	roi
lh	SN
rh	SN
```

作用：

- 告诉 Step3 从黑质 atlas 中提取双侧 SN
- 这些 ROI 会先被组装成 `sn2_mni.nii.gz`
- 然后在 Step6 中逆变换到 native T1 空间，成为后续 20 ROI 皮层下 atlas 的一部分

这 2 个 ROI 是：

- 左 SN
- 右 SN

下游用途：

- `phase1_anat/step3_subcortical_syn.sh`
- `phase1_anat/step6_distal_inverse_fusion.sh`
- `utils/phase1_anat/step6/build_subcortical_atlas.py`

修改约束：

- `roi` 名称必须和 SN atlas 目录中的 mask 文件名一致
- 行顺序同样会影响输出标签编号

## 修改时的最低检查项

如果你改了任意一个 TSV，至少需要确认这几件事：

1. `hemi` 只有 `lh` 或 `rh`
2. `roi` 名称和实际 atlas 文件名一致
3. 不小心改顺序会不会影响下游编号
4. Step3 能否成功重新生成：

```text
distal6_mni.nii.gz
distal6_labels.tsv
sn2_mni.nii.gz
sn2_labels.tsv
```

## 与 roi.tsv 的区别

不要把这两个 TSV 和 [framework/details/roi.tsv](/data/bryang/project/CNS/pipeline/framework/details/roi.tsv) 混淆。

区别是：

- `config/*.tsv`
  负责告诉 Step3 “从模板 atlas 里提取哪些原始深部 ROI”

- `framework/details/roi.tsv`
  负责定义最终 88 ROI Hybrid Atlas 的总顺序和主标签表

也就是说：

- `config/*.tsv` 决定 Step3 的模板 ROI 组装
- `framework/details/roi.tsv` 决定 Step6 最终 atlas 的全局顺序
