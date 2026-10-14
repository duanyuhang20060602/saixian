## MODEFAST：双板720p图像处理与播放/设置双模式（2026-10-14）

分支：`codex/dual-photo-720p-high-speed-switch`。

- B板执行增强、细节、亮度/对比度/饱和度、复古与反色；A板按键控制HDMI中文设置界面，保留原HMI命令。
- 正常播放沿传图窗口预读，设置期间保护当前原图并优先刷新；退出设置先补下一张，再补后两张。
- 保留50MHz板间链路、25MHz TF连续读取、A四图缓存、转场与自动轮播；连续图像调节合并50ms内的变化。
- [工程与匹配A/B bit](dual_photo_720_link6m25_read_align/README.md) · [操作及调度说明](dual_photo_720_link6m25_read_align/HDMI_SETTINGS_MENU.md) · [构建记录](dual_photo_720_link6m25_read_align/VALIDATION.md)。
- 此版针对PINFAST切图变慢的反馈修改调度，未运行功能仿真；实板切图及调参效果待确认，首次进入设置缓存未命中仍需读卡。

---

## 高速切换版本：双板 720p（2026-10-13）

分支：`codex/dual-photo-720p-high-speed-switch`。

- 板间链路 50 MHz，A 板四图缓存，B 板后台预读及缓存命中并行发送。
- TF SPI 保持 25 MHz，新增 CMD18 连续扇区读取和连续字节传输。
- 支持指定/随机转场、自动轮播及 HDMI 原图分辨率显示。
- 匹配 A/B bit、源码与打包文件见 [工程说明](dual_photo_720_link6m25_read_align/README.md) 的烧录文件链接。
- A/B 编译、布局布线及静态时序通过。本版未运行仿真，实板兼容性和实际提速待确认；此前 6.25 MHz 实板反馈不代表本版验收。

---

## 历史阶段快照：双板720p A读数据对齐版

[工程、接线与烧录说明](dual_photo_720_link6m25_read_align/README.md) · [实板状态](dual_photo_720_link6m25_read_align/HARDWARE_STATUS.json)

**2026-10-12 实板反馈：720p版本已修复，用户确认。此前误将768p图片当作720p测试图，已更正原来的干扰判断。**

匹配源码、A/B bit与打包文件见工程的 `delivery` 目录。输出1280×720，板间6.25MHz；增强/锐化与图片CRC关闭。原始1366×768目标尚未完成。

---

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
