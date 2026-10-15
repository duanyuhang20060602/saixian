## 双板 V3.1 启动恢复版

**高精度 RGB888 存在已知问题：切图可能出现横向白条、短暂闪黑，自动轮播也可能异常，尚未解决。建议使用普通精度 RGB565。**

本次启动卡住问题已由用户上板确认解决。源码见 [3.1Project](3.1Project)，问题状态见 [KNOWN_ISSUES](3.1Project/KNOWN_ISSUES.md)，[下载配套源码和 A/B 位流](https://github.com/duanyuhang20060602/saixian/releases/tag/dual-board-v3.1-boot-recovery)。

---


## 双板 V3.1

[双板 V3.1 项目与操作说明](3.1Project/README.md) · [下载 A/B 位流与素材](https://github.com/duanyuhang20060602/saixian/releases/tag/dual-board-v3.1)

# saixian

## 3.0：720P 奖杯画面与实时光效

[3.0Project](3.0Project)统一保存当前版本：HX4S20C / EG4S20BG256 单板输出 1280×720，显示冠军奖杯、节点流光、金色纸屑和墙体灯光呼吸。启动顺序为转圈、首帧显示、实时动画。

FPGA 从 TF 卡读取底图及效果标记，实时计算动画。保留原有 SDRAM 四字分组写入、双缓冲和 CRC 检查。

- TD 工程：[HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.al](3.0Project/src/td_project/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.al)。
- 配套位流：[HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.bit](3.0Project/releases/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.bit)。
- TF 卡素材：[AWARD720.DLT](3.0Project/examples/TF卡素材/AWARD720.DLT)，首帧包含在包内；当前读取方式要求文件连续存储。
- 实际 RTL 预览：[GIF](3.0Project/releases/实际RTL预览_R2.gif)。
- 验证记录：[validation.json](3.0Project/releases/validation.json)，包含源码、素材及位流校验值、仿真结果和布线时序。Setup WNS 为 +0.080 ns，Hold WNS 为 +0.027 ns。

2026-10-11 用户反馈“效果不错”；独立长时间实板测试尚未记录。历史 480×480 版本保留在 Git 提交历史中。
