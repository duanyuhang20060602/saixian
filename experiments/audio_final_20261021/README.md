# 赛显音频最终实验版：变调优化与音量增益表

本次交付为 EG4S20 音频实验版；保留 SW0、KEY3、基础播放与音频显示。主工程原有功能没有全部回集成，实验中移除的功能仍保持移除状态。

**[下载本次 Release（位流、完整工程包与清单）](https://github.com/duanyuhang20060602/saixian/releases/tag/audio-pitch-final-20261021-volume5)**

推荐烧录：`SAIXIAN_VOLUME5_BOOSTED_20261021.bit`。默认及恢复默认均为 **5 档**，范围 **0–8 档**，**0 档静音，5 档等于原8档**。原增益表 `[0,2,4,5,6,7,8,9,10]/8`，现为 `[0,6,7,8,9,10,11,12,13]/8`。原声、变调、和声共用该输出音量处理，保留有符号峰值饱和。

## 音频与交互

- 按倍率选择63 tap抗混叠滤波、Q16四点三次插值、短平滑交叉淡化与立体声波形匹配拼接。
- KEY2 短按：F0原声、F1升4半音、F2降5半音、F3原声+高7半音、F4原声+高八度；长按恢复原声。
- SW0 全频/低频分析、KEY3 波形/频谱沿用优化版，显示数据来自实际处理后音频。
- 仍为时域实验算法，低音和复杂音乐可能有颗粒感；不是无损专业变调。用户已接受本轮版本，未声称完成新增仪器实测。

## 验证

50,000组立体声逐样本定点模型比对、所有模式及双读头绕回、清空复位通过。0–8全部音量档位、静音、恢复默认、正负峰值饱和及真实顶层 HDMI/FFT 链路测试通过。效果器每采样输出461时钟、总处理最多605时钟，700时钟输入间隔测试通过。

TD 6.2.168116最终布线：建立裕量 **0.11 ns**、保持裕量 **0.027 ns**，总负裕量均为0。LUT 16896/19600，RAM9K 61/64，RAM32K 9/16，DSP 18/29。

位流 SHA256：`29d59df19071f08c6b3692e275aba7f0b4713a0b05ec48bb725d6a5365ab45ef`。`delivery/manifest.json` 是实际构建清单，冻结生产 HDL 的全部哈希；机器路径只代表原始构建位置。发布副本的 HDL 与此清单逐文件一致。`.al`仅将工程根路径改为相对路径，原始构建配置在完整包的 validation 中保留。

## 复现

Windows + Anlogic TD 6.2 + Python/NumPy + Icarus。从本目录执行：

```powershell
python tools/prepare_pitch.py
python tests/run_pitch.py
python tests/run_integration.py
./build.ps1 -TdRoot D:/TD
```

`prepare_pitch.py` 先生成适合当前路径的工程配置，再打开 `project/src/td_project/SAIXIAN_PITCH_EXPERIMENT.al`。Icarus 默认路径为 `D:/qiansai/.tools/iverilog-portable/ucrt64/bin`，换机器时需按实际位置调整测试脚本中的 BIN。FFT 和旧变调模型的验证依赖已收进 baseline，不再依赖原实验的邻接文件夹。

Git 中保留源码、脚本和机器可读摘要；位流、原始TD报告、测试日志、试听资源只放 Release 完整包，遵循仓库协作约定。试听文件均为软件模型输出，不是实板录音。历史备份和中途失败构建没有打入最终交付包。
