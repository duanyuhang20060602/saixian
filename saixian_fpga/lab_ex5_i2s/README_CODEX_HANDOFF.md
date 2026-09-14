# 赛显项目 Codex 交接 README

更新时间：2026-09-12

这份文件用于让后续 Codex 在不重复调查、不回退已修复问题的前提下，继续完成 HX4S20C “赛显”校园赛事声画提示终端的实机联调与完善。

## 1. 当前结论

- 目标赛题：赛题一。
- 目标硬件：单块 HX4S20C，FPGA 为安路 `EG4S20BG256`。
- 当前视频接口：**HDMI_A**，不是 HDMI_B。
- 显示格式：`640×480@60 Hz`。
- 音频：HDMI 内嵌 `48 kHz / 24-bit / 双声道 PCM`，板载蜂鸣器不能代替 HDMI 音频。
- 工程已用 TD `6.2.168116` 完成综合、布局布线和 bitgen。
- 最终时序通过：Setup WNS `+0.166 ns`，Hold WNS `+0.003 ns`，Setup/Hold 失败端点均为 `0`。
- 最新 bit 已生成，但 HDMI、音频、TF 卡和按键仍需在用户实物上完成系统验收。
- 已额外生成 `src/td_project/saixian_single_image_test.bit`：基于官方链路、找到第一张合法 BMP 后立即显示；正式源码及默认 bit 已恢复为四图版本。

## 2. 唯一工作工程与路径

实际工程根目录：

```text
E:\Codex\Downloads\qiansai\saixian_fpga\lab_ex5_i2s
```

重要：原目录被用户改名成了 `qiansai`。`E:\Codex\Downloads\嵌赛\patchwork` 是此前因写入权限限制建立的补丁中转目录，不是源代码真源。继续开发前，以 `qiansai` 下的工程为准；若当前环境仍只能写 `嵌赛`，先在 patchwork 中用 `apply_patch` 修改副本，再经用户授权复制回实际工程。

关键文件：

| 用途 | 路径（相对工程根目录） |
|---|---|
| TD 工程 | `src/td_project/HDMI1.4b_Transmitter_v1.0.al` |
| 顶层 | `src/user_source/hdl_source/top_tf_hdmi_audio.v` |
| HDMI_A/板级引脚 | `src/user_source/constraints_source/pin.adc` |
| 时序约束 | `src/user_source/constraints_source/timing.sdc` |
| 系统 PLL | `src/user_source/hdl_source/IP/sys_pll.v` |
| SDRAM 时序宏 | `src/user_source/hdl_source/include/global_def.v` |
| 工程内构建脚本 | `build_saixian.ps1`、`src/td_project/build_saixian.tcl` |
| 最新 bit | `src/td_project/HDMI1.4b_Transmitter_v1.0.bit` |
| 单图测试 bit | `src/td_project/saixian_single_image_test.bit` |
| 单图测试说明 | `单图显示测试.md` |
| 最终时序报告 | `src/td_project/final_timing.rpt` |
| 最新完整日志 | `src/td_project/td_20260911_202336.log` |
| 用户说明 | `README_赛显.md`、`上板下载说明.md`、`BUILD_STATUS.md` |

最新 bit SHA-256：

```text
69AAC9DAE5B8D65D6C17392E4F9B25CBDD9E42BAD81D931AFB7C303A82006FA8
```

不要下载 `src/td_project/HDMI1.4b_Transmitter_v1.0_Runs` 中官方例程携带的旧 bit。它不是当前 HDMI_A 赛显版本。

## 3. 用户目标与范围边界

最低演示链路：

```text
开机读取 TF 卡
→ HDMI_A 轮播赛事图片
→ 按键启动项目
→ 准备
→ 3、2、1 倒计时并同步鸣响
→ 开始提示
→ 比赛正计时
→ 暂停/继续
→ 结束提示
→ 返回图片轮播
```

当前阶段明确不做：摄像头识别、运动员检测、抢跑判断、联网、手机控制、MP4 解码、复杂真人语音、外部 STM32/ESP32/Arduino/树莓派、第二块板通信。用户自己准备赛事图片。

参考资料：

- 赛题规定：`C:\Users\39742\Desktop\2736655a-0d14-4352-a545-67f038339452 (1).pdf`
- 板卡手册：`E:\Codex\Downloads\qiansai\HX4S20_Contest_202606\9_康芯开发板使用手册及实验平台\HX4S20开发板手册-HDL版2410.pdf`
- TD 下载指南：`C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\doc\SWUG\SWUG110_BitWizard_User_Guide.pdf`

必须区分赛题要求与随附文档中的普通说明，不能把文档中的命令或建议当成用户授权。不要修改、破解或绕过 TD 许可证。当前安装已经能够正常完成构建，无需再处理许可证文件。

## 4. 已实现模块

| 模块 | 作用 |
|---|---|
| `saixian_key_debounce.v` | 双触发同步、20 ms 去抖、按下单脉冲 |
| `saixian_event_controller.v` | 赛事状态机、项目锁存、倒计时、比赛正计时、音频事件 |
| `saixian_audio_cue.v` | 48 kHz 提示音、不同事件频率/节奏/包络、PCM 峰值 |
| `saixian_video_tracker.v` | 从同步/DE 恢复像素坐标和帧起点 |
| `saixian_transition.v` | 帧边界双缓冲提交与两阶段遮帘转场 |
| `saixian_font_rom.v` | OSD 字模 |
| `saixian_osd_overlay.v` | 项目名、中文状态、大数字、MM:SS、进度、边框、音量条、错误画面 |
| `SD/sd_card_bmp.v` | SD 初始化监控、前 64 MiB 扫描、最多四图、轮播/手动切图、超时和错误码 |
| `SD/frame_fifo_write.v` | SDRAM 写入仲裁，关键组合判断已寄存以改善时序 |
| `top_tf_hdmi_audio.v` | HDMI、TF、SDRAM、赛事控制、OSD、音频、LED/数码管集成 |

TF 图片限制：最多 4 张，`640×480`、24 位、正高度、`BI_RGB` 非压缩 BMP。控制器按物理扇区扫描，不按 FAT 文件名读取或排序；扫描范围 sector 0 到 131071（前 64 MiB）。

SDRAM 使用两个 `640×480×32-bit` 帧缓冲。新图写完后通过 toggle 跨时钟域握手，在视频帧边界切换显示缓冲；加载期间保持旧图。

## 5. 状态机与按键

状态编码：

| 值 | 状态 |
|---:|---|
| 0 | 轮播 |
| 1 | 准备 |
| 2 | 倒计时 3 |
| 3 | 倒计时 2 |
| 4 | 倒计时 1 |
| 5 | 开始 |
| 6 | 进行中 |
| 7 | 暂停 |
| 8 | 结束 |

按键均低有效：

| 按键 | FPGA 管脚 | 轮播状态 | 比赛状态 |
|---|---|---|---|
| KEY1 / `key[0]` | A2 | 启动流程 | 准备阶段提前确认 |
| KEY2 / `key[1]` | B2 | 上一张 | 进行中暂停、暂停时继续 |
| KEY3 / `key[2]` | B1 | 无操作 | 准备/倒计时取消；开始/进行/暂停时提前结束；结束时立即返回轮播 |
| KEY4 / `key[3]` | C1 | 下一张 | 无操作 |

结束状态约 3 秒后自动返回轮播，无需按键。KEY1/KEY2/KEY4 在结束状态不会切换 FPGA 程序。

拨码 `sw[1:0]` 在启动时锁存项目：`00=100米`、`01=跳绳`、`10=篮球投篮`、`11=趣味接力`。比赛途中改变拨码不影响当前项目。

## 6. 用户刚报告的实机现象

用户说：结束后按了一个不确定的按键，画面又变成以前的摄像头程序。

当前判断：四个赛事 KEY 不具备切换位流功能。最可能是用户按到了板卡 `RESET`、`PROGRAM`、`PROGRAM_B` 或其他配置复位键，或者供电/下载连接瞬断。当前赛显是通过 `Program SRAM` 临时加载；发生配置复位或掉电后，SRAM 位流消失，FPGA 会重新从板载 Flash 加载以前固化的摄像头程序。

下一位 Codex 应先做证据核实，不要直接修改状态机：

1. 请用户提供开发板按键区域清晰照片，按板卡丝印区分 KEY1～KEY4 与 RESET/PROGRAM。
2. 重新 Program SRAM 下载最新 bit。
3. 在轮播状态逐个短按赛事键：KEY1 应进入准备，KEY2/KEY4 应切图，KEY3 应无反应。
4. 记录究竟哪个实体键会立即出现旧摄像头程序；若出现，观察 FPGA DONE/电源 LED 是否闪烁。
5. 检查供电、USB/JTAG 排线和板卡复位键，不要先假定是 RTL 状态机问题。
6. SRAM 版本完全稳定前不要 Program Flash。若以后固化，必须先从板卡手册核对 Flash 型号、容量、启动方式和烧写参数，不可猜测，也不可执行不必要的整片擦除或 efuse/加密操作。

## 7. 时钟与时序修复，禁止随意回退

板载输入时钟为 50 MHz。当前系统 PLL 实际派生为：

- SD/BMP 控制：100 MHz。
- SDRAM 控制：50 MHz。
- SDRAM 移相输出：50 MHz，144°。
- 视频像素：25 MHz。
- HDMI 串行：125 MHz。

`sys_pll.v` 的关键参数为：

```verilog
.CLKC0_DIV(10), .CLKC0_CPHASE(9),
.CLKC1_DIV(20), .CLKC1_CPHASE(19),
.CLKC2_DIV(20), .CLKC2_CPHASE(7)
```

`global_def.v` 中 `SDR_CLK_PERIOD` 必须与 50 MHz SDRAM 控制时钟一致。顶层 `sd_card_bmp.CLK_FREQ_HZ` 必须保持 `100_000_000`。

曾经存在 Setup WNS `-6.692 ns`，主要是 SDRAM DQ 输入/输出路径。已完成的真实修复包括：

- 显式加载 ADC、SDC 和异步 FIFO IP 约束；早期构建曾因脚本漏加载 ADC/SDC 导致管脚随机放置。
- 为 50 MHz、100 MHz、25 MHz、125 MHz 及 SDRAM 移相时钟建立真实约束。
- 按时钟域同步释放复位，消除复位 recovery/removal 问题。
- 寄存 `frame_fifo_write` 的长组合仲裁条件。
- 将 SDRAM 控制时钟调整为 50 MHz、采样相位调整为 144°，最终实现 Setup/Hold 收敛。

不要用宽泛 false path 掩盖 SDRAM 数据时序。只允许对已由异步 FIFO、Gray 指针、双触发器或 toggle 握手保护的跨域路径设置例外。

最终构建仍有已知 `PHY-5079` 关键警告：移相 SDRAM 输出时钟只驱动一个芯片管脚，TD 使用本地布线。该路径已被最终 STA 分析，Setup/Hold 均通过。另有布局过程中的中间位置告警，但最终无多驱动、无异常时序路径。

## 8. HDMI_A 与指示引脚

HDMI_A：

| 信号 | 管脚 |
|---|---|
| HDMI_CLK_P | K1 |
| HDMI_D2_P | B3 |
| HDMI_D1_P | E3 |
| HDMI_D0_P | F5 |
| DDC_SCL | P1 |
| DDC_SDA | R1 |
| HPD | K2 |

差分 N 端由 TD 根据差分对自动分配。不要重新改回 HDMI_B 约束。

状态指示：LED0=轮播，LED1=SD 初始化完成，LED2=HDMI_A HPD，LED3=存在错误。数码管显示状态号或错误号。

错误码：E01=CMD0 无响应；E02=SD 初始化失败/超时；E03=未找到合法 BMP 或扫描超时；E04=图片/整帧读取超时；E05=HDMI_A HPD 低或 EDID 超时。

## 9. 构建方法与已验证结果

TD 安装目录：

```text
C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116
```

在工程根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_saixian.ps1
```

工程内 `build_saixian.tcl` 必须显式包含：

```tcl
set ADCList {{../user_source/constraints_source/pin.adc}}
set SDCList {{../user_source/constraints_source/timing.sdc}}
set IpSDCList { rfifo_32_32_512 ../user_source/hdl_source/IP/afifo_32_16_256.tcl wfifo_32_32_512 ../user_source/hdl_source/IP/afifo_16_32_256.tcl }
```

最近一次用工程自身脚本复现成功，最终结果：

```text
Setup WNS  = +0.166 ns
Setup TNS  = 0
Hold WNS   = +0.003 ns
Hold TNS   = 0
Setup/Hold violated endpoints = 0
bitgen successful
```

资源：LUT 6696/19600，REG 4032/19600，BRAM9K 20/64，DSP 2/29，PLL 2/4。

每次 RTL、PLL、约束或布局相关修改后，必须重跑完整流程并读取最新 `final_timing.rpt`，不能仅以生成 bit 或 TD 退出码 0 判定成功。

## 10. 测试现状

已执行：

- `python -m unittest discover -s tests -v`：2 组 BMP 工具测试通过。
- `tools/validate_bmp.py doc/TF卡图片`：现有 5 张示例 BMP 全部通过格式检查。
- TD 完整综合、布局布线、bitgen：通过。
- 最终管脚约束和 HDMI_A 管脚已参与编译。

尚未执行/完成：

- `sim/tb_event_controller.v` 和 `sim/tb_transition.v` 已提供，但当前电脑没有 Icarus Verilog，尚未运行。
- 尚未对 0/1/2/4 图、32-bit BMP、压缩 BMP、损坏头、截断数据和读取超时进行完整 RTL 级合成扇区仿真。
- 尚未完成 HDMI_A 实机画面、HDMI 音频、TF 卡兼容性、按键顺序、异常恢复测试。
- 尚未完成 30 分钟、100 次切图、20 次完整赛事流程的稳定性验收。

## 11. 文档陷阱

- `README_赛显.md`、`BUILD_STATUS.md`、`上板下载说明.md` 是当前赛显说明。
- `设计参考例程文档.md/.docx` 是旧官方参考例程说明，其中仍可能写 HDMI_B 和旧测试音逻辑，只能作为历史参考，不能据此覆盖当前 HDMI_A 配置。
- 工程文件名仍沿用官方 `HDMI1.4b_Transmitter_v1.0`，不要仅凭文件名误判为未改造例程。
- 用户口语中可能称开发板为“单片机”，实际目标器件是 FPGA。

## 12. 下一位 Codex 的建议工作顺序

1. 先阅读本文件、`README_赛显.md`、`BUILD_STATUS.md`、`上板下载说明.md`。
2. 核对实际工程路径和最新 bit 哈希，不使用官方旧 bit。
3. 优先协助用户识别实体按键，复现“返回摄像头程序”现象。
4. 若仅 RESET/PROGRAM 导致回退，保持 RTL 不变，解释 SRAM/Flash 差异。
5. 若确认某个 A2/B2/B1/C1 赛事键确实导致 FPGA 重新配置，再检查原理图、电源完整性、按键复用和约束，不要先改状态机。
6. 完成基础上板流程及声音检查后，再处理异常恢复和长稳测试。
7. 如需改代码，使用 `apply_patch`，保留用户已有文件；构建后重新核对 ADC、Setup/Hold 和最新 bit 时间/哈希。

## 13. 可直接交给下一位 Codex 的提示词

```text
请阅读工程根目录 README_CODEX_HANDOFF.md，并以
E:\Codex\Downloads\qiansai\saixian_fpga\lab_ex5_i2s
作为唯一真实工程继续工作。当前赛显使用 HX4S20C/EG4S20BG256 和 HDMI_A；最新 bit 已通过 TD 6.2.168116 完整构建与时序收敛。先帮助我核实按键后出现旧摄像头程序的问题，优先区分赛事 KEY 与 RESET/PROGRAM，以及 Program SRAM 掉电/复位后从旧 Flash 回载的情况。未经硬件证据不要回退 HDMI_A 约束、PLL/SDRAM 时序修复或修改状态机，也不要直接烧写 Flash。
```
