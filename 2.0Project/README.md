# 赛显 2.0：SDRAM 周期刷新修复版

平台：安路 EG4S20BG256，TD 6.2.168116。此目录独立包含 2.0 工程、烧录文件、素材、动画资源与测试，不需要覆盖 1.0 工程。

## 当前版本

2026-09-27 15:22:28 构建。修复 SDRAM 时钟周期宏缺少括号导致周期刷新请求无法产生的问题，并按 EM638325 规格设置 4096 次刷新/64ms 的请求预算。50MHz 下每 765 个时钟请求一次，4096 个间隔共 62.6688ms。

24 项常规回归通过，布局种子 4，建立时间 +0.107ns、保持时间 +0.027ns，STNS/HTNS 为零。LUT 17118/19600、寄存器 9294/19600、RAM9K 37/64、RAM32K 14/16、DSP 14/29。没有降低视频时钟或放宽约束。

**这是通过仿真和布线时序的修复版，不是已完成长时间实板验证的稳定性保证。** 原问题为百米页与轮播切换后，闲置背景出现彩点；最新修复的长时间停留、切换及冷启动效果仍待实板复测。上传到独立分支不代表确认全部彩点根因已解决。

## 烧录与素材

- 唯一烧录文件：[HDMI1.4b_Transmitter_v2.0.bit](src/td_project/HDMI1.4b_Transmitter_v2.0.bit)，701792 字节。
- SHA256：`F0DF2A40BA2358375D0B9A90FF94B5363996C73B5AA1C9CA953E5740636D9801`。
- TF 卡素材：[五首 AUD 和六张 BMP](doc/TF卡上卡素材_20260925/)；五张轮播图片和独立百米背景，背景的 BMP 识别标记应保留。
- FPGA 动画：[赛果动画 RTL](src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v)；对应 `saixian_*_atlas.hex/.mif` 字模和 `doc/tools/` 生成脚本一并提供。保留蓝方/红方获胜底部文字、百米排名及领奖动画。

BitWriter 移除旧文件条目后重新添加此文件，确认时间为 15:22:28；不需要删除磁盘备份。素材与 HMI 不需要因本次刷新修复而更换。当前目录不包含重新编辑的 HMI 源文件，串口指令见功能报告。

TF 读取采用连续扇区扫描，不遍历 FAT 簇链，文件须连续存储；单独覆盖素材可能产生碎片。重新部署 TF 卡前先备份，再一次性复制该素材目录的全部文件。

## 工程与验证

- 工程：[HDMI1.4b_Transmitter_v2.0.al](src/td_project/HDMI1.4b_Transmitter_v2.0.al)。
- 构建：[build_saixian.ps1](build_saixian.ps1)。只接受新生成且建立/保持时间均合格的位流，失败候选不会替换最后合格位流。
- 常规回归：[tests/run_stability.ps1](tests/run_stability.ps1)。仅其中列出的 24 项是当前常规套件；目录内未列入的诊断/优化试验为历史资料，可能依赖已撤回候选。
- 最终时序：[final_timing.rpt](src/td_project/final_timing.rpt)。
- 最终资源：[HDMI1.4b_Transmitter_v2.0_phy.area](src/td_project/HDMI1.4b_Transmitter_v2.0_phy.area)。
- 功能、算法及修复记录：[功能与算法应用报告](doc/功能与算法应用报告.md)。

在 Windows PowerShell 中进入本目录，运行 `./tests/run_stability.ps1`，再运行 `./build_saixian.ps1`。脚本默认使用本机的 `C:/iverilog`、`C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116`，输出缓存放在 `E:/Codex/Temp`；其他电脑须调整工具路径。TD 工程文件保留原本机路径信息，若本机没有原目录，打开工程时按实际位置重新定位；HDL 文件引用为相对路径。

编译数据库、临时日志、模拟可执行文件、安装包、许可证及失败位流不随本目录发布。
