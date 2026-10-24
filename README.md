# saixian

## 5.0：双板赛显与实时浮雕奖杯

当前工程：[5.0project](5.0project)。公开版本保持 5.0；固件构建标识为 `gold-relief-native-bright-20261024`，奖杯素材修订为 `joined-model-20261024`。

- [A 板固件](5.0project/releases/PHOTO_BOARD_A_5_0.bit)、[B 板固件](5.0project/releases/PHOTO_BOARD_B_5_0.bit)。
- [TF 卡奖杯素材 RELIEF720.DLT](5.0project/examples/TF卡素材/RELIEF720.DLT)：SXDLT008，3,942,400 字节，须连续存储并配合上述两板固件。
- 杯身保留 24 个原生 576×576 视角，HDMI 输出 1280×720；默认每 10 个显示帧换角度，约 4 秒一圈。仅奖杯场景采用两倍曝光曲线和高光保护。
- 修复四根杯颈支撑、两侧把手和装饰肋线的接合缺陷；已使用上述新版固件时，本次连接修复只需替换素材。
- [按键与使用说明](5.0project/黄金浮雕奖杯使用说明.txt)、[连接修复前后对照](5.0project/releases/relief_joinfix_20261024/stem_join_comparison.png)、[软件显示参考](5.0project/releases/relief_joinfix_20261024/rtl_reference_0.png)。

A/B 两板建立与保持时序均通过。当前 75 项有效验证记录中，素材修订重跑 12 项，其余 63 项输入哈希未变并已复核；详见 [验证清单](5.0project/releases/relief_joinfix_20261024/validation.json)。此前 5.0 实板验收通过由用户反馈，本次素材修订的实板效果仍待确认。

## 3.0：720P 奖杯画面与实时光效

[3.0Project](3.0Project)统一保存当前版本：HX4S20C / EG4S20BG256 单板输出 1280×720，显示冠军奖杯、节点流光、金色纸屑和墙体灯光呼吸。启动顺序为转圈、首帧显示、实时动画。

FPGA 从 TF 卡读取底图及效果标记，实时计算动画。保留原有 SDRAM 四字分组写入、双缓冲和 CRC 检查。

- TD 工程：[HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.al](3.0Project/src/td_project/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.al)。
- 配套位流：[HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.bit](3.0Project/releases/HDMI1.4b_Transmitter_v3.0_720p_SoftFlow.bit)。
- TF 卡素材：[AWARD720.DLT](3.0Project/examples/TF卡素材/AWARD720.DLT)，首帧包含在包内；当前读取方式要求文件连续存储。
- 实际 RTL 预览：[GIF](3.0Project/releases/实际RTL预览_R2.gif)。
- 验证记录：[validation.json](3.0Project/releases/validation.json)，包含源码、素材及位流校验值、仿真结果和布线时序。Setup WNS 为 +0.080 ns，Hold WNS 为 +0.027 ns。

2026-10-11 用户反馈“效果不错”；独立长时间实板测试尚未记录。历史 480×480 版本保留在 Git 提交历史中。
