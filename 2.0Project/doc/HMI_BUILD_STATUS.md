# HMI 串口与时序修复交付记录

## 当前合格固件

- 下载：E:/Codex/Downloads/SAIXIAN_2.0_HMI_MUSIC_EXIT_20260927.bit。
- 工程内同内容位流：src/td_project/HDMI1.4b_Transmitter_v2.0.bit。
- 时间：2026-09-27 19:51:22；大小：702956 字节。
- SHA256：5524A058C0B881AF3BB74A0FA2C8F53C71ABA2F410266B3C1A4A1659CB563F59。两个文件已核对一致。
- TD 6.2.168116，EG4S20BG256，布局种子 3。
- final_timing.rpt：2026-09-27 19:51:18，Routed，Slow/Fast；SWNS +0.105ns、STNS 0.000ns，HWNS +0.024ns、HTNS 0.000ns。
- 保留视频 75MHz、SD 100MHz、存储器 50MHz 和原时序约束。
- LUT 17355/19600，寄存器 9372/19600，RAM9K 38/64，RAM32K 14/16，DSP 10/29。
- 成功构建日志：E:/Codex/Temp/saixian_hmi_tests/build_music_shared_slide_seed3.log。构建脚本核对报告、位流时间与建立/保持时序后接受。

## 本次功能

1. home.t_m 回传 TF 扫描器实际识别的有效 AUD 曲数 0–5，取代旧音频存在标志 0/1。
2. 55 08 00 00 FF FF FF：下一首音乐，末首循环；复用音轨索引、跨时钟请求和 FIFO 清空。仅轮播、非赛果、非板载设置且至少两首时执行。
3. 55 23 00 00 FF FF FF：下一帧边界退出蓝/红赛果、排名及领奖台，清除待执行的动画；重复退出不会启动动画。
4. 保留页面通知、设置同步、FPGA 计时回传和独立暂停/继续功能。

## 时序修改

动画的十一组错峰位移共享帧数乘法基值，用十一位模运算和常量偏移得到同样的 0–1200 像素位移。相比本轮未共享方案，LUT 从 17516 降到 17355；相比先前交付，DSP 从 14 降到 10。没有增加像素流水线级数，也没有将单个动画拆成不同播放段。

原有赛果文字区域提前计算和固定领奖台偏移提前计算仍保留。采用种子 3、高强度布线/布线后优化，显式执行保持时间修复。

## 验证与源码

tests/run_stability.ps1 列出的 28 项全部通过，退出码零；日志 E:/Codex/Temp/saixian_hmi_tests/regression_music_shared_slide.log 有 28 条 PASS。

新增音乐测试从 UART 引脚解码 0–5 及清零计数；发送真实 08 指令，验证循环、比赛/赛果/设置模式限制和零/单首音乐行为；验证 23 指令及非法参数。动画控制测试验证退出入场阶段、帧边界及重复退出。独立参考测试枚举 256 帧数 × 256 起始偏移（65536 组），并验证文字区域、全部领奖台位移；原几何、调色、像素延迟、音频、SDRAM、图像处理等测试均通过。

- top_tf_hdmi_audio.v：87A5A07C9CB2A6FBBC71812417A10D2DE7C79F0B27C05ED691EFB6FF6D71864F。
- saixian_hmi_uart.v：D2775B075F4800DDAD7DC4F3ACE8B27355B6EF4D18348E3D5712C02822FF617F。
- saixian_battle_result_fx_pipelined.v：4F6C4761017CAEAADA9DB80D8389571133642BF51B364FD30CAEC9D983EE8755。

## HMI 和实板边界

HMI 二进制未直接改写；已读取源文件 SHA256 43CAE3E582D42DC69C392C3C235667595F0F4A03B390B874667267C76EFE95BC。按 HMI_音乐与退出动画.md 修改按钮事件；其他页配置按 HMI_编辑器操作清单.md。

尚未完成屏幕编辑器编译、TFT 下载、FPGA 烧录和实板联调。音乐数最多五首，不统计普通 MP3/WAV。实板需核对识别曲数、切歌回环和各类动画退出。

## 历史候选

17:18:04 合格固件 B083971955351758FB42479CD348B2AFF6E7E96B615CFB2EC9DBE5C1CBFA60DC 作为历史备份，未包含音乐计数修正、08 和 23；请使用上面的新文件。

本轮多个未共享位移的布局未通过；最接近者 SWNS -0.018ns，路径在加密 HDMI 核内部 EDID/I2C 控制。计数器裁剪和全套 TimingHigh 未解决本轮布局问题，未纳入最终 RTL。失败候选不作为交付固件；独立实验存于 E:/Codex/Work/saixian_hmi_seed_sweep，日志和缓存位于 E:/Codex/Temp。
