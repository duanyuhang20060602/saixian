# TJC8048X570 与赛显 FPGA 2.0 双向串口修改说明

**音乐计数、08 切歌、23 退出动画已接入；新位流于 19:51:22 生成，28 项回归通过，最终建立 +0.105ns、保持 +0.024ns，STNS/HTNS 为零。位流与 SHA256 见 HMI_BUILD_STATUS.md。屏端修改和实板联调仍需完成。**

本次修改目标是 `2.0Project`，1.0 工程不作为本次烧录来源。HMI 源文件为 `saixian-main/saixian_UART_HMI.HMI`，未直接修改二进制文件；请在 USART HMI 编辑器内按下面说明修改并编译下载。

当前文件 SHA256：43CAE3E582D42DC69C392C3C235667595F0F4A03B390B874667267C76EFE95BC。有效记录与事件提取见 `HMI_CURRENT_EXTRACTED.json`。提取确认首页已有 `t_p/t_m/t_e`，设置页有五个滑块、两种滤镜，比赛页有 `t4/t3` 两个时间文本；结算页有 `b_red/b_blue/b_100`，但三者目前错误地发送 02。第 4 页 settle_1_8 只有标题，目前没有成绩数据录入协议，不能说它已实现八人排名上传。

## 1. 接线和串口配置

- 串口屏 TX → FPGA RX（D14）；串口屏 RX ← FPGA TX（G11）；GND 共地。
- FPGA 约束为 LVCMOS33。屏幕使用 TTL 串口接口；若实际模块配置为 RS232，须先转换，不能直接接 FPGA。具体屏幕后缀、串口模式和连接器脚位须按实物确认；屏幕电源与信号电平是两回事。
- 115200、8N1、无流控；屏幕电源单独按模块规格供电。
- Program.s 保留 `baud=115200`，添加 `bkcmd=0`，保留 `page 0`。`bkcmd=0` 关闭每条设置指令的成功/失败应答，调试时可暂时改为 3 查看屏端报错；FPGA 不解析该应答，不把发送计数当作成功确认。

屏→FPGA：7 字节 `55 CMD VALUE 00 FF FF FF`，VALUE 是二进制单字节。
FPGA→屏：ASCII 赋值指令 + 三个二进制 FF；例如 `home.t_p.txt="5"` + `FF FF FF`。两方向协议不同。

## 2. 控件属性与页面通知

首页：`t3 → t_p`（图片数量）、`t2 → t_m`（已识别有效 AUD 音乐数量 0–5）、`t5 → t_e`（IN 初始化、OK 正常、E1…E7 设备错误）。当前 HMI 已完成这三个改名。

把以下 FPGA 回写控件的 `vscope` 设置为 **全局**：

- home：`t_p/t_m/t_e`，txt_maxl 至少 2。
- settings：`h_sharp/h_bright/h_contrast/h_saturation/h_volume`，`n_sharp/n_bright/n_contrast/n_saturation/n_volume`，`bt_invert/bt_vintage`。
- game：`t4/t3`，txt_maxl 至少 5；新增数字控件 `n_state`，vscope 全局，可以隐藏。

FPGA 使用 `页面.控件.属性` 格式，所以即使切页时最后一条串口指令尚未发完，也不会因当前页面变化写错控件。跨页赋值要求 vscope 全局： https://www.tjc1688.com/contents/25/79.html

在各页面的 **初始化完成事件（后初始化）** 加入通知，告诉 FPGA 现在该回传哪一页的数据：

home：
```text
printh 55 30 00 00 ff ff ff
```
settings：
```text
printh 55 30 01 00 ff ff ff
```
game：
```text
printh 55 30 02 00 ff ff ff
```
settle_battle：
```text
printh 55 30 03 00 ff ff ff
```
settle_1_8：
```text
printh 55 30 04 00 ff ff ff
```

home 和 game 约每 250ms 回传一轮；设置只在页面通知、收到设置/恢复命令或实际档位变化时回传，避免持续改写滑块。结算页停止周期回传，没有对应的数据控件。若以后使用内置键盘页，进入时可发送 `55 30 04 00 FF FF FF` 暂停回传，退出时重新通知目标页。

## 3. 首页按钮

`b_start`，弹起事件：
```text
printh 55 01 00 00 ff ff ff
page game
```
首页 `b_music` 触摸弹起事件改为下面一行，删除原来的 01 和 `page game`，保持在 home 页：
```text
printh 55 08 00 00 ff ff ff
```
每次点击下一首，末首回到第一首；只有图片轮播、非赛果动画、非板载设置模式且至少两首时执行。音乐数统计的是扫描器识别的有效 AUD，最多五首，不统计普通 MP3/WAV 文件。

结算页新增退出动画按钮，触摸弹起事件：
```text
printh 55 23 00 00 ff ff ff
page home
```
也可放入结算页返回首页按钮。23 在下一个视频帧边界退出蓝/红获胜、排名或领奖台显示，清除待执行动画，重复发送不会重新启动动画；单独 `page home` 只切换串口屏页面，不能停止 FPGA 动画。

`b_prev`：
```text
printh 55 04 00 00 ff ff ff
```
`b_next`：
```text
printh 55 05 00 00 ff ff ff
```
`b_set` 保留 `page settings`。前后翻图只在 FPGA 轮播可操作时生效，比赛中不会翻图。

## 4. 设置页

删除原页面初始化里的 `bt_invert.val=0`、`bt_vintage.val=0`，避免每次进入页面都显示关闭，却没有关闭 FPGA 实际滤镜。滑块 maxval：锐度 3；其他四个 100；minval 都为 0。默认显示可以先设锐度 1，亮度/对比度/饱和度 50，音量 63，滤镜 0。进入后最终以 FPGA 回传为准。

在每个滑块的 **触摸弹起事件** 写下面代码；拖动事件如需本地数字预览只写对应 `n_xxx.val=h_xxx.val`，不要连续发命令。

锐度：
```text
n_sharp.val=h_sharp.val
printh 55 10
prints h_sharp.val,1
printh 00 ff ff ff
```
亮度：
```text
n_bright.val=h_bright.val
printh 55 11
prints h_bright.val,1
printh 00 ff ff ff
```
对比度：
```text
n_contrast.val=h_contrast.val
printh 55 12
prints h_contrast.val,1
printh 00 ff ff ff
```
饱和度：
```text
n_saturation.val=h_saturation.val
printh 55 13
prints h_saturation.val,1
printh 00 ff ff ff
```
音量：
```text
n_volume.val=h_volume.val
printh 55 14
prints h_volume.val,1
printh 00 ff ff ff
```

反色 `bt_invert` 弹起：
```text
printh 55 15
prints bt_invert.val,1
printh 00 ff ff ff
```
复古 `bt_vintage` 弹起：
```text
printh 55 16
prints bt_vintage.val,1
printh 00 ff ff ff
```
双态按钮弹起时发送的是切换后的 val；用屏幕调试器确认按钮 0/1 与发送内容一致，关闭不需要额外写固定 0。

恢复默认 `b_reset` 弹起，只需：
```text
printh 55 1f 00 00 ff ff ff
```
FPGA 恢复后会回写五个滑块、数字及滤镜状态。连续点击恢复默认、但值已经默认时，为确保再次刷新显示，可加一条设置页通知：
```text
printh 55 30 01 00 ff ff ff
```

0–100 最终映射到 FPGA 0–8 档；回传代表值为 0/13/25/38/50/63/75/88/100。滑块发送 60 后显示 63 是档位量化结果，不是传输错误。锐度保持 0–3。

## 5. 比赛页计时、暂停、继续

删除 game 页初始化中清零 `n_total/n_min/n_sec/j0` 与 `tm0.en=1` 的旧代码。把 `tm0.en` 初值设为 0，删除 tm0 原来的本地累计秒数、60 秒停止及写 `t4/t3` 的代码。初始化完成事件：
```text
tm0.en=0
printh 55 30 02 00 ff ff ff
```

时间由 FPGA 直接更新：
```text
game.t4.txt="MM:SS"
game.t3.txt="MM:SS"
game.n_state.val=N
```
这些是 FPGA 发出的命令示例，不要在屏幕端写固定时间循环。FPGA 保留原比赛准备/倒计时流程，准备与倒计时期间显示 00:00，进入运行后开始累计；暂停停止计时。状态：0 轮播，1 准备，2/3/4 倒计时 3/2/1，5 开始，6 运行，7 暂停，8 结束。

`b_pulse` 暂停弹起，替换旧 02：
```text
printh 55 06 00 00 ff ff ff
```
`b_continue` 继续弹起：
```text
printh 55 07 00 00 ff ff ff
```
`b_end` 结束弹起，删除原有本地计时清零代码：
```text
printh 55 03 00 00 ff ff ff
page settle_battle
```
06 只在 FPGA 运行状态触发暂停，07 只在暂停状态触发继续；重复点击不会反向切换。旧 02 仍兼容，但不建议新界面使用。

`j0` 旧代码是假定比赛总时长为 60 秒的进度。本次没有用户确认的比赛总时长，所以删除旧进度计算并把 j0 隐藏；不能用它暗示真实比赛进度。旧 `n_total/n_min/n_sec/t_tmp` 可以保留但不再由旧定时器写时间。若需要根据 n_state 控制暂停/继续按钮可操作性，可另加一个 UI 定时器，只更新按钮状态，不计时、不发控制指令。

## 6. 结算页：必须修正三条错误指令

当前文件 `b_blue/b_red/b_100` 都发送 02，这是暂停命令，不能选赛果。

`settle_battle.b_blue` 弹起：
```text
printh 55 20 00 00 ff ff ff
```
`settle_battle.b_red` 弹起：
```text
printh 55 21 00 00 ff ff ff
```
`settle_battle.b_100` 弹起：
```text
printh 55 22 00 00 ff ff ff
```
`b_home` 保留 `page home`。

注意：现有赛果动画模块只在 FPGA 回到轮播且没有进入设置模式时接受选择；03 结束后 FPGA 有约 3 秒结束展示。请等首页状态对应的设备已回轮播再点击赛果。提前点击不会排队，也不是串口丢帧。屏幕留在结算页并不意味着 FPGA 内部已经处于轮播。

22 是现有百米赛果动画入口，不是八名选手成绩上传。settle_1_8 目前没有成绩录入控件，因此本次只提供页面通知，不虚构完整成绩协议。

## 7. 当前尚未接入的首页文字输入

`t_flowing/t_title1` 事件发 `23` + 文本 + `0D 0A`（即 #文本+回车换行），与 55 命令帧不同；当前 FPGA 不支持任意文本滚动/标题上传，本次不把它宣称为已接入功能。两个现有条件使用 `空字符串 && 某非空字符串`，条件本身也无法同时成立，需要按你的实际输入意图改为合适条件。不要把文字发送与当前已实现的按钮/参数控制混淆。

## 8. 下载和联调

1. 编辑器选择实际 TJC8048X570 对应后缀，800×480；修改以上控件和事件，编译通过后下载到屏幕。
2. 用串口调试器验证首页按钮与滑块发出的十六进制字节，例如亮度 50 是 `55 11 32 00 FF FF FF`，不是 ASCII 字符 "50"。
3. 下载 HMI_BUILD_STATUS.md 标记的最新合格位流，重新添加到烧录工具并核对 SHA256。
4. 双向连接后首页检查图片数、有效 AUD 音乐数和 IN/OK/E 状态；进入设置页检查默认 1/50/50/50/63，再改音量、滤镜、恢复默认。
5. 开始→等待准备与倒计时→暂停→重复暂停→继续，观察 HDMI 和屏幕计时一致；结束后等待 FPGA 返回轮播，再选蓝/红/百米动画。
6. 断电重启、屏幕单独重启、快速切页后检查刷新。屏幕启动的 00/88 消息不会触发比赛动作；后初始化通知会重新建立页面选择。

RTL 仿真不是屏端编译或实板验证。发送计数只说明 UART 命令已发完，不能证明屏幕接收成功；实际 HMI vscope、txt_maxl 和事件仍须按以上步骤配置验证。