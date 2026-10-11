# saixian

## 3.0：720P 冠军奖杯与实时光效

[3.0Project](3.0Project)保存当前奖杯版本：单板 HX4S20C / EG4S20BG256 输出 1280×720，启动转圈、显示首帧，再播放聚光灯发散与汇聚，同时实时叠加奖杯流光、墙体呼吸与金色彩带。

当前彩带参考真实金色纸带飘落状态，采用 16 个倾斜翻面姿态、轻微弯曲和随角度变化的金属亮暗，保持适中的数量。彩带由 FPGA 实时生成。

- [TD 工程](3.0Project/src/td_project/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.al)
- [配套位流](3.0Project/releases/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.bit)
- [TF 素材 AWARD720.DLT](3.0Project/examples/TF卡素材/AWARD720.DLT)：本次彩带修改未改变素材内容，已有配套素材无需重复更换。
- [效果预览 MP4](3.0Project/releases/聚光灯_配套数据预览.mp4) · [GIF](3.0Project/releases/聚光灯_配套数据预览.gif)
- [验证记录](3.0Project/releases/validation.json)

TF 素材包含一张带效果标记的底图与 120 张 160×90 光场，聚光灯循环约 5.94 秒。光场储存在外部 SDRAM，FPGA 使用滚动行缓存进行空间与时间插值；全工程使用 24/64 块 BRAM、10098 个 LUT 和 17 个 DSP。此设计不是完整像素视频解码器，TF 文件需要连续存储。

当前位流已通过彩带 ROM 65536 个样本、输出延迟 921600 个像素和预览参考模型 2233232 个 RGB 样本核对。滚动缓存的完整扫描、CRC、读取竞争与错误诊断测试记录一并保留。布线 Setup WNS +0.121 ns、Hold WNS +0.027 ns，TNS 均为零。

预览为软件合成，彩带参考模型与 16 个 RTL 采样帧逐像素核对；视频光场插值约 60.606 fps，彩带样本约 30.303 fps，并非实板录像。此前滚动行缓存版本已获用户实板运行反馈，当前 16 姿态彩带位流仍待实板验收。历史版本保留在 Git 历史中。
