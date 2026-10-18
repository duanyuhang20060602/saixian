# 双板 V3.1：启动恢复版

> **当前候选 AV_B_WINNERS：** 保留用户反馈较好的四字分组写入版本，A 音频缓冲减至 4096，FFT/波形分析迁至 B，恢复共享渲染的红蓝获胜动画；本轮不加入流体效果。两板最终时序通过，音频分析迁移及动画仍待上板验收。详见 [配套说明与资源对比](delivery/AV_B_WINNERS_README.md)。

用户已上板确认本版启动卡住问题解决。保留单板频谱/波形移植、透明背景、音频修复开关、首首音乐就绪后的音画同步启动和 DLT 奖杯功能；新增 V2.0 百米成绩、排名与领奖台动画，操作见 [V2.0 赛果动画](V2_RESULT_ANIMATION.md)。

## 烧录

- A：`delivery/PHOTO_BOARD_A_720P_V3_1_AV_B_WINNERS.bit`
- B：`delivery/PHOTO_BOARD_B_720P_V3_1_AV_B_WINNERS.bit`

本候选使用 25 MHz 链路；A/B 两板均须更新后重新启动，不可与此前 50 MHz 位流混用。奖杯素材沿用现有 `AWARD720.DLT`；百米赛道背景可使用 `delivery/SAIXIAN_100M_1280x720_24bit.bmp`，需放入 B 板 TF 卡照片集（最多 6 张）。

## 版本状态

本次 A 板位流已通过布局布线时序检查（Setup WNS +138 ps，Hold WNS +27 ps，零违例），包含 V2.0 百米成绩动画、KEY4 长按控制和高色彩读路径优化。高色彩切图及动画效果仍需实机验证。对应构建指标和 SHA-256 见 `delivery/board_a_v31_v2_sprint_key4_hicolor_timing_pass.json`；启动恢复说明与首错诊断见 [BOOT_RECOVERY.md](BOOT_RECOVERY.md)。上述指标属于此前启动恢复版本。当前候选 A/B 指标分别见 `delivery/board_a_v31_av_b_winners.json`、`delivery/board_b_v31_av_b_winners.json`。

## 水滴切图配套位流（2026-10-18）

新增 RGB565 水滴切图，默认启用；普通轮播 KEY1 切图触发。A/B 必须配套烧录 `delivery/FLUID_DROP_AB_20261018.zip` 内的位流，J2 接线不变。RGB888 保持现有精度并回退滑动。A 使用 57 RAM9K、14 RAM32K；B 使用 60 RAM9K、12 RAM32K。两板最终 setup/hold 时序通过，实板待验收。细节与命令见 `delivery/FLUID_DROP_README.md`。此前 AV_B_WINNERS 配套包保留。

## 水滴作为可选切换方式（FLUID_SELECT）

当前推荐配套包为 `delivery/FLUID_SELECT_AB_20261018.zip`。默认恢复为随机，水滴在菜单第 7 项选择，HMI 命令 `55 18 07 00 FF FF FF`。普通模式随机池包含水滴并避免连续重复，RGB888 随机池排除水滴。A 本轮重新编译，原领奖提示长组合路径已按帧锁存/寄存文字；B 复用经全部源码/位流哈希核对一致的 FLUID_DROP 版本。A：13186 LUT、11076 REG、57 RAM9K、14 RAM32K、12 DSP；B：13007 LUT、8963 REG、60 RAM9K、12 RAM32K、10 DSP。两板最终时序通过，实板待验收。详见 `delivery/FLUID_SELECT_README.md` 与 `FLUID_PORTABILITY_20261018.md`。

## 优先流体效果已移植（FLUID_PRIORITY，2026-10-18）

当前配套包 `delivery/FLUID_PRIORITY_AB_20261018.zip` 新增 8=液态金属、9=卷页、10=分列翻转，并保留 7=水滴、0=随机和 1–6 原切换方式。菜单最后新增“音乐边光”，默认关闭；HMI 开启 `55 1C 01 00 FF FF FF`，关闭值为 00。三种新切换用于 RGB565，边光支持 RGB565/RGB888 的普通照片轮播。详见 `delivery/FLUID_PRIORITY_README.md`。

三种效果共用当前行缓存/混合/重建，投影倒数表只增加 1 RAM9K；边光不新增 FFT/全屏缓存。A：14505 LUT、11945 REG、58 RAM9K、14 RAM32K、14 DSP；B：13007 LUT、8963 REG、60 RAM9K、12 RAM32K、10 DSP。A/B 均本轮重新构建，最终 setup/hold 时序通过、TNS 为 0，实板待验收。新增菜单字库流水线维持原 21 周期对齐，最终边光 RGB/DE/SOF/EOL 一起增加固定 5 周期。旧版配套包保留。

## 全部转场平滑改版（FLUID_SMOOTH，2026-10-18）

当前配套包为 `delivery/FLUID_SMOOTH_AB_20261018.zip`。普通与流体转场统一 48 次逐帧推进（约 0.8 秒），普通位移采用缓入缓出，流体独立线性相位，取消原两帧保持并减慢水滴环纹的时间推进。菜单、HMI、J2 接线和 RGB888 回退规则不变。SDRAM 四字写入后 10 周期等待保持原值。

本轮重新构建 A：14561 LUT、11968 REG、58 RAM9K、14 RAM32K、14 DSP；Setup WNS +0.059 ns，Hold WNS +0.022 ns，TNS 均为 0。B 复用全部记录源码/位流哈希一致的 FLUID_PRIORITY B，未重新编译；已烧录该 B 的用户只需更新 A。未运行新的功能仿真，实板待验收。详见 `delivery/FLUID_SMOOTH_README.md`，其中也记录了按 RGB565/RGB888 区分写后等待的后续评估；8/6 周期尚未证明安全，未加入本包。

## 次一档流体与 RGB565 零额外等待（FLUID_SECOND，2026-10-18）

新增 11=整张卡片翻转、12=手风琴、13=飘带；普通模式随机池包含新效果。HMI `55 18 0B/0C/0D 00 FF FF FF`，也可在设置中选择后按 KEY1 切图。三者复用现有八行缓存、倒数表及投影/弯曲乘法器；RGB888 固定选择时回退滑动。48 级逐帧转场保留。

A/B 的 RGB565 写后额外等待改为 0，RGB888 保留 10，门限在写请求阶段锁存；保留四字组、必要收尾状态、刷新与仲裁保护。请配套烧录 `delivery/FLUID_SECOND_AB_20261018.zip` 的 A/B 两个位流。A：15128 LUT、12007 REG、58 RAM9K、14 RAM32K、14 DSP；B：12847 LUT、8940 REG、60 RAM9K、12 RAM32K、10 DSP。两板最终 setup/hold 通过、TNS 为 0。未运行新的功能仿真，零等待后的白条与新几何实板效果仍待验收。详见 `delivery/FLUID_SECOND_README.md`。旧版文件保留。

## RGB565 改为六周期等待（FLUID_SECOND6，2026-10-18）

当前配套位流为 `delivery/FLUID_SECOND6_AB_20261018.zip`，A/B 两板均完整重编。RGB565 写后额外等待由 0 改为 6，RGB888 保留 10；门限按写请求锁存。卡片翻转、手风琴、飘带、原有效果和 48 级时间轴继续使用。

A 首次构建在开场进度→文字/颜色路径出现 -0.105 ns setup 违例；已提前锁存加载阶段解码，保持 RGB VIDEO_DELAY 对齐，重新构建后通过。A 最终 setup/hold WNS +0.090/+0.022 ns；B +0.059/+0.021 ns，两板 TNS 均为 0。A：15166 LUT、11996 REG、58 RAM9K、14 RAM32K、14 DSP；B：12774 LUT、8934 REG、60 RAM9K、12 RAM32K、10 DSP。未运行新的功能仿真，实板待验收，旧位流和失败证据保留。详见 `delivery/FLUID_SECOND6_README.md`。

## 波形/频谱更新修复候选（AV_REFRESH6，2026-10-18）

针对“音乐正常、图形长时间停住”，A 改用本地实际接受的 PCM 数作为快照发布位置，并保留播放进度门控；分析包失败后保持轮询到期、满足音频水位时及时重试；SPI 包间 CS 高电平延长到约 1 微秒。保留 RGB565 六周期、RGB888 十周期等待、48 级转场与全部已接入效果。修正来自源码风险排查，尚无板上抓取证明唯一根因。

配套包 `delivery/AV_REFRESH6_AB_20261018.zip`；两板完整重编、setup/hold TNS 为 0，A WNS +0.131/+0.022 ns，B +0.059/+0.021 ns。A 另拆分了频谱比较/配色的现有流水与设置变化判断，维持视频总延迟。未运行新的功能仿真，实板待验收。详见 `delivery/AV_REFRESH6_README.md`。
