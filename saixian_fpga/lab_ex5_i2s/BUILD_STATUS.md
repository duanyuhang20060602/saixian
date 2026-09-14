# 构建状态（2026-09-11）

- 目标器件：`EG4S20BG256`
- 顶层：`top`
- TD 版本：`6.2.168116`
- 输出接口：HDMI_A，640×480@60 Hz，HDMI PCM 音频
- 完整流程：综合、布局布线、bitgen 均成功
- 最终 Setup：WNS `+0.166 ns`，TNS `0 ns`，失败端点 `0`
- 最终 Hold：WNS `+0.003 ns`，TNS `0 ns`，失败端点 `0`
- 资源：LUT 6696/19600，REG 4032/19600，BRAM9K 20/64，DSP 2/29，PLL 2/4
- BMP 工具测试：2 组单元测试通过；示例目录 5 张 BMP 全部通过格式校验
- RTL testbench：已提供，但本机未安装 Icarus Verilog，尚未执行
- 已知告警：移相后的 SDRAM 输出时钟只驱动一个芯片管脚，TD 将其使用本地布线并给出 `PHY-5079`；该路径已纳入最终时序分析且 Setup/Hold 均通过

## 可下载文件

本次构建生成的文件：

`src/td_project/HDMI1.4b_Transmitter_v1.0.bit`

对应时序报告：

`src/td_project/final_timing.rpt`

不要选用 `src/td_project/HDMI1.4b_Transmitter_v1.0_Runs` 内随官方例程附带的旧 bit；旧产物不是本次 HDMI_A 赛显构建。

## 复现构建

在工程根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\build_saixian.ps1
```

脚本使用 `C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116`，并显式加载 `pin.adc`、`timing.sdc` 及异步 FIFO 约束。每次重建后仍应重新核对 `final_timing.rpt` 中 Setup/Hold WNS 均不小于 0。

## 尚未由软件验证的内容

当前没有条件替代真实硬件验证 HDMI 显示、显示器扬声器、TF 卡兼容性和按键手感。首次下载建议先使用 SRAM/JTAG 临时配置，完成基本流程验证后再考虑固化。
