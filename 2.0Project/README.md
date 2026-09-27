# 赛显 2.0：HMI 双向串口与 SDRAM 刷新修复版

平台：安路 EG4S20BG256，TD 6.2.168116；串口屏 TJC8048X570。此目录独立包含 2.0 工程、素材、动画资源与测试。

## 当前版本

2026-09-27 19:51:22 构建，布局种子 3。新增首页 t_p/t_m/t_e 状态回传、设置参数回传、FPGA 比赛时间/状态回传、页面通知及独立暂停/继续指令；保留 SDRAM 周期刷新修复。

28 项回归全部通过。最终布局布线：建立时间 +0.105ns，保持时间 +0.024ns，STNS/HTNS 均为零。LUT 17355/19600、寄存器 9372/19600、RAM9K 38/64、RAM32K 14/16、DSP 10/29。视频时钟仍为 75MHz，未放宽时序约束。

新增 08 循环切歌、23 退出赛果动画；t_m 显示已识别有效 AUD 音乐数量 0–5。编辑器代码见 [HMI_音乐与退出动画.md](doc/HMI_音乐与退出动画.md)。动画十一组位移共享帧数乘法基值，65536 组独立参考比较通过。

为收敛时序，赛果动画的固定领奖台偏移提前到逐帧更新，文字高度判定提前寄存；新增独立几何参考测试确认坐标、动画及流水线延迟保持一致。

**这是已通过仿真和完整布线时序的新固件；尚未完成修改后 HMI 的编辑器编译、屏幕下载和实板联调，不能把它描述成实板长时间稳定性保证。**

## 烧录与 HMI 修改

- 工程内位流：[HDMI1.4b_Transmitter_v2.0.bit](src/td_project/HDMI1.4b_Transmitter_v2.0.bit)，702956 字节，2026-09-27 19:51:22。
- SHA256：`5524A058C0B881AF3BB74A0FA2C8F53C71ABA2F410266B3C1A4A1659CB563F59`。
- 同内容下载副本：`E:/Codex/Downloads/SAIXIAN_2.0_HMI_MUSIC_EXIT_20260927.bit`。
- 屏幕编辑器逐步操作：[HMI_编辑器操作清单.md](doc/HMI_编辑器操作清单.md)。
- 完整事件代码和协议：[HMI_双向串口修改说明.md](doc/HMI_双向串口修改说明.md)。
- 构建、测试与交付记录：[HMI_BUILD_STATUS.md](doc/HMI_BUILD_STATUS.md)。

HMI 当前工程归档：[saixian_UART_HMI.HMI](hmi/saixian_UART_HMI.HMI)，说明见 [hmi/README.md](hmi/README.md)。未直接改写二进制；按说明在 USART HMI 编辑器修改控件属性和事件，再编译下载。旧版本不包含这些双向同步功能；在 BitWriter 移除旧文件条目，重新添加本次文件并核对时间及哈希。

屏 TX→FPGA D14，屏 RX←FPGA G11，GND 共地；115200、8N1，使用 TTL 接口。比赛计时以 FPGA 为准，屏端旧 tm0 本地计时需要关闭。现有文字输入及八人成绩上传尚未接入，见完整说明。

## 素材与工程

- TF 卡素材：[五首 AUD 和六张 BMP](doc/TF卡上卡素材_20260925/)，本次串口更新不要求更换素材。
- FPGA 动画：[赛果 RTL](src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v)，配套 `saixian_*_atlas.hex/.mif` 保留。
- TD 工程：[HDMI1.4b_Transmitter_v2.0.al](src/td_project/HDMI1.4b_Transmitter_v2.0.al)。
- 构建：[build_saixian.ps1](build_saixian.ps1)，失败或过期的候选不会替换最后合格位流。
- 回归：[tests/run_stability.ps1](tests/run_stability.ps1)，当前常规套件为脚本列出的 28 项。
- 最终时序：[final_timing.rpt](src/td_project/final_timing.rpt)。
- 资源：[HDMI1.4b_Transmitter_v2.0_phy.area](src/td_project/HDMI1.4b_Transmitter_v2.0_phy.area)。
- 功能、算法及历史修复：[功能与算法应用报告](doc/功能与算法应用报告.md)。

TF 读取采用连续扇区扫描，不遍历 FAT 簇链，文件须连续存储。重新部署 TF 卡前先备份，再一次性复制全部素材；单独覆盖素材可能产生碎片。

PowerShell 进入本目录，运行 `./tests/run_stability.ps1`，再运行 `./build_saixian.ps1`。脚本使用本机 `C:/iverilog` 与 `C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116`，测试缓存和构建备份放在 `E:/Codex/Temp`。其他电脑应调整工具路径。编译数据库、失败位流和临时日志不作为交付固件。