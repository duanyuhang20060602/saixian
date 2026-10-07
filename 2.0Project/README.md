# 赛显 2.0：真实音频频谱与双声道波形

**2026-10-07 资源优化候选：** 保留成功 2.0 的 SDRAM/HDMI/FIFO、VGA 清晰版缩放与增强代码，只优化素材目录和文件头判定。LUT 15252→14565（少 687，4.50%），寄存器 10326→9749；RAM9K 55、RAM32K 11、DSP 11 不变。建立 +0.110ns、保持 +0.022ns，总违例零；原 47 项回归与新增 2 项通过。**新位流实板待验证，原成功默认位流仍保留。**

当前源码对应 [HDMI1.4b_Transmitter_v2.0.bit](releases/HDMI1.4b_Transmitter_v2.0.bit)，请重新 Add 此文件烧录；不与 `src/td_project` 内的旧默认位流混用。[匹配源码与报告完整包](releases/HDMI1.4b_Transmitter_v2.0.zip)、[本轮说明与 GitHub 清晰度修复核对](doc/资源优化与清晰度保持.md)。以下 2026-10-03 记录属于本轮前的对照版本。

平台：安路 EG4S20BG256，TD 6.2.168116；当前实物串口屏 `TJC8048T070_011R`，800×480。原 `TJC8048X570_011` 工程仍保留。

## 当前版本（2026-10-03）

首页显示来自实际 HDMI 音频的 1024 点 FFT、32 根频谱柱；KEY3 长按一秒在频谱与双声道波形间切换，持续按住不重复切换，首页短按松开进入设置。设置和比赛保留原 KEY3 操作。模式和显示快照在帧边界切换，不改 HMI、音乐素材或时钟约束。

上一轮自写 FFT 常量压缩、共享元数据 RAM、动画无损字典 ROM、图片插值范围化简及 OSD 流水线重排，释放 RAM9K 5 块和 RAM32K 3 块；用户反馈该版实测良好。本轮参考安装包例程，自写共享转场地址核心、参数化窄计数器及 BMP 字节并行边界比较，直接接入正式 2.0。

本轮整机 LUT 从 15987 降到 15252/19600（77.82%），减少 735 个；RAM9K 55/64、RAM32K 11/16、DSP 11/29。完整 TD 布线建立/保持 WNS +0.284/+0.030 ns，TNS 均为零，STA 覆盖率 99.96%。47 项回归、3579360 次地址参考、1090920 周期帧读取与 4500072 周期计时器输出对照通过。FFT、波形和动画源码沿用上一轮合格版。

当前默认位流与 `src/td_project/SAIXIAN_2.0_LIGHT_EXAMPLES_20261003.bit` 匹配。**本轮位流实板验收待进行。** 使用 `build_saixian.ps1` 复现面积优化参数；GUI 默认策略可能打包超容量。详见 [轻量例程与本轮实现验证](doc/赛显轻量例程与2.0优化_20261003.md)、[可复用例程](examples/saixian_lightweight/README.md)；[上一轮存储优化](doc/资源优化研究与实现_20261003.md) 和 [2026-10-02 音频可视化](doc/真实音频可视化_20261002.md) 为历史交付记录。

## 上一版本（2026-10-01）

已从 GitHub 分支 `codex/saixian-2.0-sdram-refresh` 提交 `18908e72221d1d081aa67af064bbbc71eee9cf25` 整合最新 RTL、测试及位流。轮播态 KEY2 短按松开选择蓝方、长按满 1 秒选择红方；胜方画面停稳后 KEY2 直接推进排名，不再插入另一胜方画面。比赛态暂停/继续、设置态减小参数、HMI 指令均保留。原 VGA 清晰版 R2、SDRAM 刷新、五首音乐和配套图片素材继续使用。真实排名不属于当前要求，本次未新增成绩采集或真实排名。

在上述 GitHub 版本基础上，本机新增首页上一张/下一张响应修复：SDRAM 0/1/3 帧槽缓存当前及前后邻图，读卡忙时可提交已缓存目标，等待读卡时重复点击合并，转场时保留一次最新方向请求，防止五次请求循环抵消；槽 2 仍专用于比赛背景。调度增加相邻编号与扇区地址流水线，BMP 边界比较和增强范围门限采用等价简化。详情见 [五次请求抵消修复与复验](doc/五次连点与方向错乱修复_20261001.md)。本次未修改屏幕工程和素材。

39 项 FPGA 回归通过，含真实 UART 接收器到切图调度及转场的逐张操作仿真；新屏同步检查通过。本机 TD 完整重建、布局种子 12，最终布线建立余量 +0.115ns，保持 +0.027ns，STNS/HTNS 均为零，STA 覆盖率 99.97%；LUT 17380/19600、寄存器 9525/19600、RAM9K 38/64、RAM32K 14/16、DSP 10/29。相对上一版 NAV_CACHE 少 40 LUT、7 个寄存器，RAM、DSP 和外部帧缓存相同。已复现并修复慢读卡期间五次请求抵消；用户逐张点击也卡住的现场症状尚未复现，不能认定完整根因已排除。新位流整机实测尚待下载后验证。

## 烧录、接线与验证

- **当前 FPGA 下载文件**：[轻量例程优化版](src/td_project/SAIXIAN_2.0_LIGHT_EXAMPLES_20261003.bit)，691316 字节，SHA256 `90EFFA219A0B14F9A25E56BEB5C3870A658E66C74D606A588168D0F597F04876`；默认 `HDMI1.4b_Transmitter_v2.0.bit` 与其一致。用户反馈实测良好的 [上一轮存储优化版](src/td_project/SAIXIAN_2.0_COMPACT_STORAGE_20261003.bit) 和 [音频可视化版](src/td_project/SAIXIAN_2.0_REAL_AUDIO_VISUAL_20261002.bit) 保留用于回退。
- **当前新屏已烧录文件**：[saixian_TJC8048T070.tft](hmi/saixian_TJC8048T070.tft)，源工程 [saixian_TJC8048T070.HMI](hmi/saixian_TJC8048T070.HMI)。屏序列号 `E467C05117335E28`，PC 下载时 COM10，运行 115200、8N1。本次更新无需重烧新屏。
- 新屏已通过官方编辑器编译和下载，实物串口查询的 18 个反馈控件、五个页面通知通过；已修复 T0 背景切图兼容问题。详情见 [屏幕交付与验证](hmi/README.md)。原 X570 文件只用于对应旧屏。
- **接线**：屏 TX→J1 第 1 脚 GPIOA_0/D14；屏 RX←J1 第 2 脚 GPIOA_1/G11；GND→J1 第 12 或 30 脚。新屏信号为用户确认的 3.3 V TTL；VCC 按屏幕电源标注，不能把信号电平当成供电电压。接 FPGA 前拔下 USB 转 TTL 的 TX/RX，避免发送端并联。
- **完整现场操作**：[新屏接线与整机验证](doc/新屏接线与整机验证_20261001.md)，含供电、HDMI_A、最新 FPGA 下载、播放、参数回写、比赛计时、KEY2 和故障定位。
- 本次整合前备份：`E:/Codex/Work/saixian_integrate_20261001_18908e7/before`。整合证据：[文件清单](doc/validation/integration_18908e7_manifest.json)、[34 项回归记录](doc/validation/integration_18908e7_regression_20261001.txt)。
- 切图修改前备份：`E:/Codex/Work/saixian_navigation_20261001`。当前修复前备份：`E:/Codex/Work/saixian_navigation_wrap_fix_20261001`。本次证据：[交付清单](doc/validation/navigation_wrap_20261001_manifest.json)、[39 项回归记录](doc/validation/navigation_wrap_20261001_regression.txt)、[旧版失效记录](doc/validation/navigation_wrap_20261001_before_failure.txt)。

比赛计时以 FPGA 为准，HMI 已关闭旧屏端 tm0 本地计时。首页自定义文字上传和八人成绩采集仍未接入；已有排名动画为演示。原实机稳定性反馈对应此前使用的位流，不替代本次新位流现场复验。

## 素材与工程

- TF 卡素材：[五首 AUD 和六张 BMP](doc/TF卡上卡素材_20260925/)，本次串口更新不要求更换素材。
- FPGA 动画：[赛果 RTL](src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v)，配套 `saixian_*_atlas.hex/.mif` 保留。
- TD 工程：[HDMI1.4b_Transmitter_v2.0.al](src/td_project/HDMI1.4b_Transmitter_v2.0.al)。
- 构建：[build_saixian.ps1](build_saixian.ps1)，失败或过期的候选不会替换最后合格位流。
- 回归：[tests/run_stability.ps1](tests/run_stability.ps1)，当前常规套件为脚本列出的 47 项。
- 最终时序：[final_timing.rpt](src/td_project/final_timing.rpt)。
- 资源：[HDMI1.4b_Transmitter_v2.0_phy.area](src/td_project/HDMI1.4b_Transmitter_v2.0_phy.area)。
- 功能、算法及历史修复：[功能与算法应用报告](doc/功能与算法应用报告.md)。
- 本轮 GitHub 算法及资源取舍：[GitHub FPGA 算法与资源审计](doc/GitHub_FPGA算法与资源审计_20260928.md)。

TF 读取采用连续扇区扫描，不遍历 FAT 簇链，文件须连续存储。重新部署 TF 卡前先备份，再一次性复制全部素材；单独覆盖素材可能产生碎片。

PowerShell 进入本目录，运行 `./tests/run_stability.ps1`，再运行 `./build_saixian.ps1`。脚本使用本机 `C:/iverilog` 与 `C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116`，测试缓存和构建备份放在 `E:/Codex/Temp`。其他电脑应调整工具路径。编译数据库、失败位流和临时日志不作为交付固件。
