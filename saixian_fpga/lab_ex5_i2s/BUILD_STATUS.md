# 构建状态（2026-09-17）

- 目标器件：`EG4S20BG256`
- 顶层：`top`
- TD 版本：`6.2.168116`
- 当前完整功能输出：HDMI_A，1280×720 渐进扫描，约 60.6 Hz（75 MHz 像素时钟），HDMI PCM 音频
- 图片输入：1280×720 至 1920×1080、24 位、BI_RGB；较大图片由 FPGA 实时缩小到 1280×720
- 完整流程：综合、布局布线、bitgen 均成功
- 帧缓存：每个 32 位 SDRAM 字打包两个 RGB565 像素，保持 1280×720 空间分辨率，将平均读带宽约从 55.9 Mword/s 降至 27.9 Mword/s
- 最终 Setup：WNS `+0.118 ns`，TNS `0 ns`，失败端点 `0`
- 最终 Hold：WNS `+0.003 ns`，TNS `0 ns`，失败端点 `0`
- 资源：LUT 10703/19600，REG 5786/19600，BRAM9K 20/64，BRAM32K 1/16，DSP 2/29，PLL 2/4
- 字库：1007 条非空 16×16 字模显式映射到 1 个 BRAM32K，避免深层分布式 LUT 查表路径
- 图片数量：最多扫描并轮播 5 张；扫描窗口保留前 256 MiB，但找到至少一张后若连续 5 秒无新增图片便正常结束并加载已有图片
- 已恢复功能：六种图片转场、开机动画、赛事 OSD、进度条、比赛流程、HDMI 音频和 32 柱轻量级频谱；比赛状态不显示黑色频谱底条
- 本次修复：一秒计数器由25位扩为27位，使75 MHz下能够连续推进3、2、1、开始及比赛计时；OSD改为单一640x480逻辑画布实时缩放覆盖完整1280x720输出，标题、倒计时、绿色边框、进度条和频谱不再重复且范围随720p全屏映射；TF控制器增加1秒独立冷启动稳定等待，初始化超时由3秒延长至8秒，失败后仍自动复位重试；互斥OSD模式改为显式互斥渲染以保证75 MHz时序
- BMP 工具测试：2 组单元测试通过；项目内全部 17 张 BMP 通过格式校验
- RTL testbench：已提供，但本机未安装 Icarus Verilog，尚未执行
- 硬件状态：标准720p时序、五张图片轮播、中文字模和倒计时连续推进已实机确认；全屏OSD映射及TF卡冷启动增强已通过完整编译和静态时序，等待断电冷启动上板确认

## 可下载文件

正式位流：

`src/td_project/HDMI1.4b_Transmitter_v1.0.bit`

同内容的完整功能及时序通过备份：

`src/td_project/HDMI1.4b_Transmitter_v1.0_FULLSCREEN_OSD_TF_COLD_BOOT_TIMING_PASS_20260917.bit`

五图版本明确命名备份：

`src/td_project/HDMI1.4b_Transmitter_v1.0_1280x720_5images_20260916.bit`

正式位流 SHA-256：

`D897DDE108D963D2BA6CCE3A7F62387922BDF392985DEEC702B3E59F5AEDD104`

对应时序报告：

`src/td_project/final_timing.rpt`

旧 640×480 稳定版保留为：

`src/td_project/HDMI1.4b_Transmitter_v1.0_640x480_stable_20260916.bit`

不要选用 `src/td_project/HDMI1.4b_Transmitter_v1.0_Runs` 内随官方例程附带的旧 bit。

## 图片说明

`doc/convert`、`doc/convert/output_bmp` 和 `doc/TF卡图片` 内的比赛示例 BMP 已统一为 1280×720。桌面五张高清素材的工程副本位于 `doc/TF卡五图_720p`。两张 1536×1024 PNG 重新缩放生成，其余只有 640×480 原始数据的图片采用 Lanczos 等比例放大并补黑边，因此满足格式要求，但不会凭空增加真实细节。

## 复现构建

在工程根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_saixian.ps1
```

脚本使用 `C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116`，并显式加载 `pin.adc`、`timing.sdc` 及异步 FIFO 约束。每次重建后仍应重新核对 `final_timing.rpt` 中 Setup/Hold WNS 均不小于 0。

## 上板验收重点

首次下载先使用 SRAM/JTAG 临时配置。当前版本应先显示不带文字框的开机动画，图片读取完成后再显示 OSD；默认约每五秒切换图片，并按六种效果轮换。两位数码管中的图片计数应与 TF 卡成功识别数量一致（目标为 5）。重点确认五图均可轮播、转场无撕裂、文字字模正常、比赛界面无黑色频谱底条、无声时 32 柱静止、有声时才变化。全部稳定后再固化到 Flash。
