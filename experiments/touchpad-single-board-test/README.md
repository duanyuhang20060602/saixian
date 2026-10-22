# 单板串口屏触控测试

面向现有 HX4S20 / EG4S20BG256 的 HDMI 输出板（原 A 板）。仅需一块 FPGA 板、串口屏 TJC8048T070 和 HDMI 显示器，不需要 B 板、板间排线、TF 卡、SDRAM 图像或音频输入。上电直接显示 1280×720 测试画面。

## 烧录与接线

完整物理接线、CH340监听和故障定位见 [WIRING.md](WIRING.md)。配套陶晶驰工程为 [hmi/MOUSE.HMI](hmi/MOUSE.HMI)，编辑器使用说明见 [hmi/README.md](hmi/README.md)。

写入 `delivery/TOUCHPAD_SINGLE_BOARD_TEST.bit`，顶层 `top_touch_single`。不要与原双板工程的 A/B 位流混淆。

| 连接 | FPGA 板 |
|---|---|
| 屏 TX | J1-1 / D14，hmi_uart_rx |
| 屏 GND | GND |
| HDMI 显示器 | 板载 HDMI 接口 |
| 屏 RX（可选） | J1-2 / G11，hmi_uart_tx |

串口115200、8N1。屏按额定要求供电；D14为3.3V逻辑输入，屏TX必须兼容，否则需电平转换。CH340仅作监听时TXD悬空、RXD接屏TX、共地。

本测试只接收串口数据，FPGA TX保持空闲高电平，不会向屏端 `t_tip` 写入文字。坐标和统计显示在 HDMI 上。屏 RX 可以不接。

## 屏端设置

继续使用之前已经验证的触控页及按下/定时器/弹起事件，无需改变坐标协议。按住建议每20ms发送一帧：

```text
A6 XL XH YL YH DOWN SUM FF FF FF
SUM = (A6 + XL + XH + YL + YH + DOWN) mod 256
```

X、Y是800×480屏的原始坐标，小端；DOWN为1表示按住，0表示松手。默认上电启用触控，直接发送A6帧即可测试。也兼容原触控页的启用/关闭命令：

```text
55 31 01 00 FF FF FF  启用
55 31 00 00 FF FF FF  关闭
```

若使用现有返回按钮关闭了触控，再次进入页面需发送启用命令。无需等待原系统照片加载或轮播。

## 测试步骤

1. 上电即出现标题 `SINGLE BOARD TOUCHPAD TEST`，中心白色箭头，红、绿、蓝及CLEAR按钮。
2. 滑动触控区，箭头按相对位移移动，增益2倍，边缘限位；抬手重新按下不跳到屏端绝对坐标。
3. 移到RED、GREEN、BLUE并轻触，目标按钮颜色变亮，TAP加一。按住拖动后松手不会触发点击。
4. 点击CLEAR，接收计数、错误计数、轻触计数及颜色选择复位；光标位置不复位。
5. MODE为0时不响应移动和点击，仍统计收到的合法帧；发送启用命令恢复。

轻触要求接触至少20ms且小于250ms，整次接触任一方向偏离起点不超过8个屏像素。超过180ms没有触点采样会取消接触。

| HDMI区域 | 说明 |
|---|---|
| RAW X / Y | 最近合法触点帧的原始坐标 |
| DOWN | FPGA当前判定的接触状态，断流超时后归零 |
| CUR X / Y | HDMI光标坐标，初始(640,360) |
| MODE | 触控模式启用状态 |
| RX | 合法触点帧数，启用/关闭命令不计入 |
| ERR | 接收模块发现的协议/校验错误数，不代表能检测所有电气错误 |
| TAP | 合法轻触数，点击空白处也计数 |

所有坐标及计数均用**十六进制**显示，例如01D8=472，0280=640，0168=360。计数器为16位，溢出回零。诊断行按帧刷新。

按钮命中坐标（左闭右开）：RED x128–416，GREEN x496–784，BLUE x864–1152，三者y400–528；CLEAR x496–784、y592–656。

## 源码和复现

- `rtl/top_touch_single.v`：独立顶层、视频PLL、720p HDMI、串口输入。
- `rtl/touch_test_core.v`：接收帧、相对指针、轻触、按钮及统计。
- `rtl/touch_test_scene.v`：字体、按钮、实时诊断、光标，两拍视频流水线。
- `rtl/saixian_hmi_uart.v`、`rtl/photo_touchpad.v`：沿用已验证的触控协议和手势实现。
- `rtl/vendor`：从AV_REFRESH6工程复用的视频PLL、复位、HDMI编码/串化模块，保留原文件注释。
- `constraints`：仅约束本测试的端口，不含SDRAM/板间接口。

运行 `python tools/test.py` 做UART至按钮联动和画面测试；默认Icarus位于上级`.tools/iverilog/bin`，也可用环境变量`IVERILOG`指定。

运行 `python tools/build.py` 完成综合、布局布线、保持修复、最终时序检查及位流交付。默认TD安装在`C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116`；换机器需相应修改`tools/build.py`和`project/build.tcl`中的安装路径。脚本自动更新工程路径。工程为`project/TOUCHPAD_SINGLE_TEST.al`。

构建报告、资源和时序见`delivery/build_report.json`。仿真预览为`tests/preview.png`，不是实板截图。完成工具检查仍需按上述步骤进行实板验收。
