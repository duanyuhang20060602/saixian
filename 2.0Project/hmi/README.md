# 新屏 TJC8048T070_011R 已烧录（2026-10-01）

当前整合匹配基于 GitHub 提交 `18908e7` 的首页切图修复版 `SAIXIAN_2.0_NAV_WRAP_FIX_20261001.bit`（SHA256 `A29EEC942532A252D504911C89644C3935E794C9271563D6EDA5C2C6227FFC4E`）；HMI 协议未改变，新屏不需要重烧。整机接线与复验见 [新屏接线与整机验证](../doc/新屏接线与整机验证_20261001.md)，切图专项见 [当前切图修复说明](../doc/五次连点与方向错乱修复_20261001.md)。

实物串口握手和官方编辑器均识别为 `TJC8048T070_011R`，序列号 `E467C05117335E28`，USB-SERIAL CH340 `COM10`，电阻触摸、16 MB Flash、800×480。用户确认新屏信号为 3.3 V；本次未用仪器复测电平。

- 专用源工程：`saixian_TJC8048T070.HMI`；下载文件：`saixian_TJC8048T070.tft`。
- 保留原 X570 工程。T0 不支持的透明控件改用背景图 0 的切图；32 个控件显式指定 `picc=0`。未删掉现有控制功能。
- 编译 0 错误、0 警告；TFT 2858540 字节；最大页面 RAM 1860/3584 字节。
- 官方 USART HMI 1.68.1 下载完成。下载波特率 230400，启动运行仍为 115200、8N1、bkcmd=0。
- 实物串口复查：18 个全局反馈控件读取成功；五个业务页面均返回正确的 `55 30 page 00 FF FF FF` 通知，sendme 页号一致，无图片编号错误；检查后回到首页。
- 验证记录：`TJC8048T070_FLASH_VERIFIED.json`、`TJC8048T070_SERIAL_VERIFIED.json`、`TJC8048T070_HMI_SYNC_VERIFIED.json`。源工程检查增加未指定切图编号检查，防止实物返回 04 错误。
- 本次验证了 PC 到屏幕的通信及页面协议；新屏接入 FPGA 后的实际触控、参数回写和比赛操作还需在整机上验证。匹配原稳定 FPGA 位流，不需要因屏幕型号改变而重烧 FPGA。

# TJC8048X570 屏幕同步修复交付（2026-10-01）

`saixian_UART_HMI.HMI` 已通过 USART HMI 1.68.1 原生编辑器修改、保存及编译，型号保持 `TJC8048X570_011`，800×480。SHA256：`02ADE545D67EE7B50CE14CB42D40A8F5E12EB7DF34A15D9017928DFD2A8CBC44`。

可下载屏幕固件：`saixian_UART_HMI.tft`，2547916 字节，SHA256：`4DC10464D86F1B27684F4B28AFD731EED84B735E1737CC98AE01F250F2922CBB`。编辑器编译结果：0 错误、0 警告。HMI 是编辑源文件，TFT 才是屏幕下载文件。

当时同步修复验证所用 FPGA 固件（历史版本）：`../src/td_project/HDMI1.4b_Transmitter_v2.0.bit`，SHA256：`79CA9BCA38D3A0BA82D6009BE1D6976010CB3500EF284655788A1F872B2A1A68`。该段记载的是当时的屏幕修复；当前 FPGA 位流见本页首段。

修复包括：18 个回写控件设为全局；五个业务页面发送 30 页面通知；关闭并清空 game.tm0 屏端计时；暂停/继续使用独立 06/07；新增隐藏 n_state；隐藏固定 60 秒进度及旧计时辅助数字；设置页不再自行清零滤镜，恢复默认后请求回写；启动设置 bkcmd=0。

本版本包含音乐数量回传、08 切歌、23 退出动画和既有双向参数/时间同步。home.b0、home.b1 的自定义文字发送和 FPGA 字库扩展未实现，屏幕中保留的文字输入控件不代表 FPGA 支持该功能。

保存文件检查：`../tests/check_hmi_sync.py`；本次有效记录和属性报告：`HMI_SYNC_VERIFIED.json`。匹配协议的 `tb_hmi_bidirectional` 回归通过，覆盖页面回写、重复暂停/继续、非法值和超时恢复。

用户于 2026-10-01 反馈新版 FPGA 代码经过多次实机验证且稳定。本次新 TFT 尚未下载到实物屏幕；下载后核对首页状态、设置回写、开始/暂停/继续/结束及退出动画。下载目标应与工程型号 `TJC8048X570_011` 一致。

双向接线：屏 TX→FPGA D14，屏 RX←FPGA G11，GND 共地，TTL、115200、8N1。通过 USART HMI 编辑器打开 HMI 后下载，或按屏幕手册下载本目录 TFT。

修改前备份：`E:/Codex/Work/saixian_hmi_sync_20261001/saixian_UART_HMI_before.HMI`，SHA256：`54A957C58BE1A133200B858CF1F93E6388175E164F3129C4996058E05D560E60`。编译截图：`E:/Codex/Temp/saixian_hmi_sync_20261001/compiled_final.png`。旧 `HMI_CURRENT_EXTRACTED.json` 与历史操作文档不能作为当前工程的属性证据。
