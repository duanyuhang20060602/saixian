# saixian

## 3.0：720P 冠军奖杯与实时光效

[3.0Project](3.0Project)保存当前实板反馈效果良好的版本。HX4S20C / EG4S20BG256 单板输出 1280×720：启动转圈，显示首帧，随后播放聚光灯发散、汇聚和移动效果，同时保留奖杯流光、墙体灯光呼吸与金色彩带。

TF 素材包含一张带效果标记的完整底图和 120 张 160×90 光场。FPGA 逐帧读取并检查 CRC，使用两块光场缓冲区进行空间与时间插值，同时实时叠加彩带、流光和呼吸。此版本不属于完整像素视频解码器。

- TD 工程：[HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.al](3.0Project/src/td_project/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.al)。
- 配套位流：[HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.bit](3.0Project/releases/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.bit)。
- TF 素材：[AWARD720.DLT](3.0Project/examples/TF卡素材/AWARD720.DLT)，复制到 TF 卡根目录；首帧已包含在包内，当前读取方式要求连续存储。此素材必须与本次位流配套更新。
- [新版合成预览 MP4](3.0Project/releases/聚光灯_配套数据预览.mp4)：使用新彩带 RTL 渲染和光场插值参考合成，非实板录像。预览灯光为 30 fps，彩带样本为 12 fps，不代表实板帧率。
- [验证记录](3.0Project/releases/validation.json)：包含源码、素材与位流校验值、仿真结果及布线时序。

此次修复取消彩带的 2 倍最近邻放大，改为原生 32×32 面积采样抗锯齿；光束改用柔和高斯截面，光场帧数由 60 增至 120，并修正时间插值步进及亮度量化。流光与墙体呼吸保留。

942080 个光效 RGB 像素比对、完整 720P 扫描、120 张光场 CRC、带读取停顿的 720 个连续显示节拍、循环、暂停恢复和显示时序检查通过。布线后的 Setup WNS 为 +0.040 ns，Hold WNS 为 +0.030 ns；素材与图像缓冲合计占用 6,924,800 字节 SDRAM。

2026-10-11 用户实板反馈“效果挺不错”。独立长时间实板测试尚未记录。旧版代码和素材保留在 Git 历史中。
