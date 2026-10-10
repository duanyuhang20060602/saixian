# saixian

## 本分支：双板 FPGA 图片传输，B → A

**分支 `codex/dual-board-1366x768-transfer-v1` 专门发布双板代码及 bit 流，重点为两个板子的图片传输协议与握手。**

- [双板工程、角色与 bit 下载](dual_board_1366x768_transfer/README.md)
- [板间传输代码、接线与状态数字](dual_board_1366x768_transfer/TRANSFER.md)
- 1366×768 / 60Hz；B 内置图 → A 接收 / SDRAM / HDMI 已由用户确认正常。
- SD 图片版本同时保留，固定纹波仍待定位，未标注为修复完成。

## 3.0：单板 TF 动图播放

[3.0Project 工程与使用说明](3.0Project/README.md)包含 TD 工程、Verilog 源码、引脚/时序约束、已验证位流、TF 素材和验证报告。

- 开发板：HX4S20C / EG4S20BG256；HDMI_A 输出 1280×720，原素材 480×480 居中，周围黑边。
- 启动：转圈 → 首帧额外停留约 1 秒 → 原 27 帧动图循环。SW1 暂停/继续。
- [打开 TD 工程](3.0Project/src/td_project/HDMI1.4b_Transmitter_v3.0.al)。
- [下载 QuadWrite 位流](3.0Project/src/td_project/HDMI1.4b_Transmitter_v3.0_QuadWrite.bit)，BitWriter 选择 PROGRAM_SRAM。
- TF 卡素材：[TROPHY.DLT](3.0Project/examples/TF卡素材/TROPHY.DLT)，首帧包含在包内；当前读取方式要求文件连续存储。
- 验证：完整 27 帧及循环、暂停恢复、像素比对、视频带宽和布线时序通过。2026-10-10 用户上板反馈“效果非常好”；未进行独立长时间实板测量。

QuadWrite 按官方 SDRAM 四字分组规则修正补丁写入，并保留掩码、写入排空和 CRC 检查。具体依据与历史故障见[资料复核](3.0Project/doc/安路资料复核.md)，软件/时序记录见 [validation.json](3.0Project/releases/validation.json)。

原有版本继续保留在仓库中。
