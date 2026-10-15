# 双板 V3.1：单板频谱、波形与音频修复移植

基于用户确认正常的 V3.1 奖杯、开机动画版本。本次移植来源固定为
`duanyuhang20060602/saixian` 的 `d27ae79126429f1a25a65e42f8fe95571da5c0df`，
`2.0Project/src/user_source/hdl_source/` 内的 `saixian_audio_visualizer.v` 和
`saixian_audio_repair.v`。

## 使用

两块板均须更新本套 bit。TF 卡中的照片、音乐及 `AWARD720.DLT` 保持原格式，无需添加频谱图片。

- A 板 KEY3 进入设置，KEY1 逐项选择。
- “音频显示”：KEY2 选频谱，KEY4 选波形。
- 新增末项“音频修复”：KEY4 开启，KEY2 关闭；默认关闭，恢复默认值后也关闭。
- KEY3 退出设置。设置保存在本次上电期间。
- KEY1 切照片、KEY4 短按进入/退出奖杯、奖杯内 KEY2 暂停/继续等 V3.1 操作保持。

## 与单板相同的部分

频谱使用 1024 点 FFT、去均值、Hann 窗、32 个频段和峰值保持。左右声道分别计算后合并能量，
反相立体声不会相互抵消。频谱从左到右为低频到高频，依据实际 48 kHz 播放音频计算。

波形保留 1024 个采样内每四点的左右声道最小值和最大值，共 256 组，使用触发捕获和双缓冲。
左声道青色，右声道橙色，重叠部分白色。已移除原来的单频估计绘图和单声道抽点波形。

修复保持单板的孤立尖峰处理、慢速直流消除、63 抽头 FIR、峰值保护和干湿渐变算法。
关闭时也经过与湿声对齐的 32 采样延迟，约 0.67 ms；开关以 256 个采样渐变，约 5.33 ms。
该滤波器会衰减高频，开启后听感会比关闭时柔和；它不用于还原已经丢失的音频内容。

## 双板适配

修复位于 B 板：背景音乐 → 修复 → 提示音混合 → 原双板音量 → SPI。
A 板分析最终送入 HDMI 的音频，因此频谱、波形会反映修复和音量变化。
音量档位沿用已确认的双板版本，未改为单板增益表。

SPI 请求字预留 bit 0 传递修复开关。单独切换修复不清空 A 音频 FIFO、不切换曲目 epoch，
通过渐变过渡；已排队音频播完后才能听到新设置。
B 板将每个采样的准备时刻从前一字 bit 29 提前到 bit 16，约有 400 个 100 MHz 时钟供约
335 周期的修复计算及混音使用。仍保持 128 采样一包、3.75 MHz SPI 和 A 板 48 kHz 输出。

A 板分析缓存改用空闲 32K RAM，避免超过器件的 9K RAM 数量。
尖峰判断和乘法器输入增加寄存器以适配 B 板 100 MHz；数值算法和样本延迟保持。

A 板图形沿用现有 OSD 管线，增加网格、真实频谱柱和峰值、双声道波形；整体 HDMI 图像仍为
26 周期延迟。原有比赛文字、图片、奖杯动画和黑底加载动画保留。
DLT 和图像链路 CRC 保持关闭；原控制协议的校验未改动。

## 验证

`python tools/test_audio_port.py` 可重跑六项音频验收。

- 真实左右声道双频、反相声道、直流抑制、256 组峰谷读取通过。
- 异步 75/100 MHz 双板 SPI 连续 1280 采样逐个比较通过，包含修复开启、关闭和发送时限。
- 13 项设置导航、默认关闭、开启/关闭、回绕和恢复默认值通过。
- 8192 采样修复测试（与原单板输出逐采样一致）：1 kHz 增益 +0.11 dB；8 kHz 增益 -60.08 dB；
  30000 幅度孤立尖峰的输出峰值 27；正负 10000 直流输入末段绝对均值约 1467。
  这些是特定测试向量的 RTL 仿真结果，不代表任意录音的降噪量。

开机动画、奖杯首帧运动和奖杯控制回归结果见 `tests/results/award_v4_results.json`。
双板构建、源文件 SHA256 和最终时序见 `delivery/board_a_manifest.json`、
`delivery/board_b_manifest.json`。本候选版本仍需实板确认画面和声音。

## 重新构建

在工程根目录运行 `python tools/configure_projects.py`，然后分别运行
`python tools/release.py snapshot board_a` 和 `python tools/release.py snapshot board_b`。
在对应 `projects/board_a/src/td_project` 或 `projects/board_b/src/td_project` 目录，使用 TD 6.2.168.116
执行 `td_commands_prompt.exe build_board.tcl`，将输出保存为该目录的 `award_build.log`。
回到工程根目录运行 `python tools/release.py collect board_a`、`python tools/release.py collect board_b`。
收集步骤会拒绝旧 bit、变化的源文件或负时序余量。

运行 `python tools/test_audio_port.py` 进行音频验收；运行
`python tools/test_award_v4.py --only tb_boot_v4 tb_award_entry_v4 tb_award_mode_v4`
进行继承功能回归。`v4` 仅为历史测试文件名，当前交付版本名为 V3.1。
所有检查通过后，运行 `python tools/package_audio_port.py` 生成包含源文件、双板 bit 和验证证据的压缩包。
