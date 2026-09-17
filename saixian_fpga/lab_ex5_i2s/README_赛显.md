# 赛显：校园赛事声画提示终端

本工程基于康芯官方 `lab_ex5_i2s`，目标板为 HX4S20C / EG4S20BG256。当前接口已改为 **HDMI_A**，不再使用 HDMI_B。

## 已实现

- TF 卡前 64 MiB 物理扇区扫描，识别最多 5 张 `1280×720 至 1920×1080、24 位、BI_RGB` BMP，并在 FPGA 内实时缩放到 1280×720。
- SDRAM 双帧缓冲；新图写完后通过跨时钟域 toggle 握手，在视频帧边界启动遮帘转场并切换缓冲，加载期间保持旧图。
- 5 秒自动轮播；轮播态支持上一张/下一张。
- 赛事流程：轮播 → 准备 → 3/2/1 → 开始 → 进行 → 暂停/继续 → 结束 → 轮播。
- 正计时 `MM:SS`，暂停冻结，最大 `99:59`。
- FPGA 实时叠加项目、中文状态、大倒计时、计时、进度条、闪烁边框及 HDMI 音频音量条。
- 48 kHz / 24-bit 双声道 HDMI PCM；倒计时、开始、暂停、继续、结束采用不同音序。
- E01～E05 状态画面、LED 和数码管提示；HDMI_A HPD 上升沿自动重读 EDID。
- 两个 PLL 锁定后延迟释放复位，四个板载按键全部留给交互。

## 操作

| 输入 | 轮播状态 | 赛事状态 |
|---|---|---|
| KEY1 | 启动流程 | 准备阶段提前确认 |
| KEY2 | 上一张 | 暂停 / 继续 |
| KEY3 | — | 提前结束；准备/倒计时取消 |
| KEY4 | 下一张 | — |
| SW1～SW2 | 选择 100米 / 跳绳 / 篮球投篮 / 趣味接力；启动时锁存 | 不再改变本场项目 |

四键均为低有效，含双触发同步、20 ms 去抖和单脉冲输出。

LED0=轮播态，LED1=TF 初始化完成，LED2=HDMI_A HPD，LED3=存在错误。数码管显示当前状态号或错误号。

## 图片准备

你可以自行找图。转换命令（需要 Pillow）：

```powershell
python .\tools\convert_bmp.py 原图.jpg 输出.bmp
python .\tools\validate_bmp.py 输出.bmp
```

安全复制工具只接受 Windows 识别出的可移动盘根目录，不格式化、不删除、不覆盖：

```powershell
python .\tools\prepare_tf_copy.py .\我的图片 F:\
```

重要限制：官方控制器并不解析 FAT 文件系统，而是从 sector 0 开始逐扇区搜索 BMP 头。建议先在 Windows 中确认正确盘符，再手动将卡格式化为 FAT32，然后一次性复制 1～5 张图片并安全弹出。任何格式化操作都必须由你核对盘符后执行，本工程脚本不会代做。

## 错误码

| 代码 | 含义 |
|---|---|
| E01 | CMD0 在 3 秒内无响应，通常为未插卡 |
| E02 | 卡有早期响应，但初始化未在 3 秒内完成 |
| E03 | 扫描结束，没有合法 BMP |
| E04 | BMP 加载或整帧写入超过 5 秒 |
| E05 | HDMI_A HPD 为低，或 HPD 拉高后 2 秒内未收到 EDID 数据 |

E01/E02 在卡随后成功初始化时自动清除；HDMI 拔插会重新触发 EDID。板上没有独立的 TF 卡检测脚，已初始化后在空闲期直接拔卡无法即时识别，通常会在下一次读取时表现为 E04；实机应使用断电插拔卡。

## 工程与构建

- TD 工程：`src/td_project/HDMI1.4b_Transmitter_v1.0.al`
- 顶层：`src/user_source/hdl_source/top_tf_hdmi_audio.v`
- HDMI_A 引脚：`src/user_source/constraints_source/pin.adc`
- 时序约束：`src/user_source/constraints_source/timing.sdc`
- 自检 testbench：`sim/tb_event_controller.v`、`sim/tb_transition.v`
- 上板步骤：`上板下载说明.md`
- 后续 Codex 交接：`README_CODEX_HANDOFF.md`
- 当前单图上板测试：`单图显示测试.md`

当前工程已使用 TD 6.2.168116 完成综合、布局布线和 bitgen。可在工程根目录运行 `build_saixian.ps1` 复现构建；脚本会显式加载 HDMI_A 引脚与时序约束。最新结果和 bit 路径见 `BUILD_STATUS.md`。

## 上板验收顺序

1. 断电插入已准备好的 TF 卡，HDMI 线接 HDMI_A，再上电。
2. 确认显示轮播、HDMI 声音设备锁定，测试 KEY2/KEY4 切图。
3. 依次验证启动、3/2/1、开始、计时、暂停、继续、结束、返回。
4. 分别测试空卡、坏 BMP、HDMI 拔插；记录错误码与恢复结果。
5. 上板后连续运行 30 分钟并执行 100 次切图、20 次完整流程；这些属于实机验收，不能用编译结果代替。
