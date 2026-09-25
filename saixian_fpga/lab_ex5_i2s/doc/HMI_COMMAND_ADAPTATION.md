# 陶晶驰串口屏命令适配

源工程：saixian-main/saixian_UART_HMI.HMI，原文件未修改。
提取工具：tools/extract_hmi_commands.py（仓库根目录运行）。
证据：doc/hmi_ui/hmi_extracted.json，含 SHA256、有效记录偏移、事件文本及属性原始值。

## 有效工程与协议

容器首部为 19 个 28 字节记录；提取时仅使用删除标志为 0 的有效记录，并校验范围。
有效 Program.s 位于 7361378，波特率 115200。文件其他位置的 9600 属于废弃记录。
有效页面为 0.pa/home、1.pa/settings、2.pa/game。
串口为 115200、8 数据位、无校验、1 停止位。
命令帧：55 CMD VALUE 00 FF FF FF；VALUE 是二进制单字节，不是 ASCII 数字。
启动串 00 00 00 FF FF FF 88 FF FF FF 不产生控制动作。

| CMD | 屏幕事件/含义 | VALUE | FPGA |
|---|---|---|---|
| 01 | 开始比赛 | 00 | start_pulse |
| 02 | 暂停 / 继续 | 00 | pause_pulse，切换语义 |
| 03 | 结束比赛 | 00 | finish_pulse |
| 04 | 上一张 | 00 | prev_pulse，仅轮播模式 |
| 05 | 下一张 | 00 | next_pulse，仅轮播模式 |
| 10 | h_sharp 锐度 | 0–3 | setting_id 0 |
| 11 | h_bright 亮度 | 0–100 | setting_id 1 |
| 12 | h_contrast 对比度 | 0–100 | setting_id 2 |
| 13 | h_saturation 饱和度 | 0–100 | setting_id 3 |
| 14 | h_volume 音量 | 0–100 | setting_id 4 |
| 15 | bt_invert 反色 | 0/1 | 新增 setting_id 5 |
| 16 | bt_vintage 复古 | 0/1 | 新增 setting_id 6 |
| 1F | 恢复默认 | 00 | reset_defaults_pulse，同时关闭滤镜 |

0–100 映射到既有 0–8 档，保持原图像/音量硬件结构。锐度直接对应 0–3 档。
复古实现为亮度加暖色的低成本近似；同时开启时先复古、再反色。
滤镜位于既有像素寄存器之前，不增加 RGB/DE/VS 延迟，只影响背景图。
接收器新增 40 个比特周期未收到完整字节则丢弃残缺帧；非法开关值拒绝。
现有 K2 蓝方动画流程不变；HMI 本身没有专用动画命令。

## 已知屏幕侧限制（不能等同于双向同步）

- 设置页全部滑块初值为 0；FPGA 默认锐度 1，亮度/对比度/饱和度 4 档，音量 5 档。页面初值不代表 FPGA 状态。
- 恢复按钮仅把两个滤镜按钮归零并发送 1F，没有更新五个滑块显示。
- 页面初始化把滤镜按钮归零但未向 FPGA 发关闭命令，再入页面可能显示与实际状态不一致。
- 暂停与继续均发送 02，无法在 FPGA 端从报文字节区分两种按钮。重复点击会切换回来。
- game 页定时器自行计数到 60 秒，不是 FPGA 计时回传；两边可能不同步。
- 当前 hmi_uart_tx 固定空闲高电平，没有状态回传。此次没有擅自改动 HMI 二进制工程、比赛时长或指令语义。

## 接线与验证

现有约束：FPGA RX = D14，TX = G11。屏 TX 接 FPGA RX，并共地。
IO 约束为 LVCMOS33；接线前核对具体屏幕串口电平，不要直接接 RS232 或未经确认的高电平输出。

仿真：
    iverilog -g2012 -s tb_hmi_adapter -o sim/hmi_adapter.vvp sim/tb_hmi_adapter.v src/user_source/hdl_source/saixian_hmi_uart.v src/user_source/hdl_source/top_tf_hdmi_audio.v
    vvp sim/hmi_adapter.vvp

覆盖 13 个编号、启动噪声、非法开关、未知命令、超时、坏帧恢复、滤镜颜色。
上板仍需逐一验证屏幕按钮、滑块端点、恢复默认及 K2 动画。未烧录或实测串口连接。
