# HMI 编辑器操作清单（TJC8048X570）

2026-10-01：下述同步修改已在 `2.0Project/hmi/saixian_UART_HMI.HMI` 通过原生编辑器完成，已编译输出 `saixian_UART_HMI.tft`，0 错误、0 警告。当前下载与哈希以 [屏幕交付说明](../hmi/README.md) 为准。下文保留为维护操作参考，不要使用 `saixian-main` 中的旧副本。

## A. Program.s

进入工程的 Program.s，全局启动区使用：
```text
baud=115200
bkcmd=0
printh 00 00 00 ff ff ff 88 ff ff ff
page 0
```
有其他必要的全局变量声明请保留，不要重复定义。串口 115200、8N1，无流控。

## B. 控件属性

在左侧页面列表选中页面，再点击控件，在右侧属性栏改 `vscope=全局`。

| 页面 | 需要全局的控件 | 其他属性 |
|---|---|---|
| home | t_p、t_m、t_e | 文本 txt_maxl≥2；三个名称分别对应原 t3、t2、t5，当前文件已改名 |
| settings | 五个 h_ 滑块、五个 n_ 数字、bt_invert、bt_vintage | h_sharp maxval=3；其他滑块 maxval=100；minval=0 |
| game | t4、t3、新增 n_state | 两个文本 txt_maxl≥5；n_state 为数字控件，可设 vis 隐藏，但不要删除 |

新增 n_state：工具箱添加“数字”控件，把 objname 改成 `n_state`，设置 `vscope=全局`，val=0。在 game 后初始化可写 `vis n_state,0` 隐藏。新固件给它写入比赛状态码。

## C. 页面后初始化事件

选中页面背景（不是按钮），打开下面“后初始化事件”标签。各页面加下面对应一行，保留其他必要布局代码。

| 页面 | 后初始化代码 |
|---|---|
| home | printh 55 30 00 00 ff ff ff |
| settings | printh 55 30 01 00 ff ff ff |
| game | printh 55 30 02 00 ff ff ff |
| settle_battle | printh 55 30 03 00 ff ff ff |
| settle_1_8 | printh 55 30 04 00 ff ff ff |

settings 页面：删除原初始化里 bt_invert.val=0 和 bt_vintage.val=0，不要每次进入都自行覆盖状态。

game 页面后初始化建议完整改为：
```text
tm0.en=0
vis n_state,0
printh 55 30 02 00 ff ff ff
```
删除原来 n_total/n_min/n_sec/j0 清零和 tm0.en=1 的本地计时启动代码。

## D. 按钮触摸弹起事件

点选按钮，切到“触摸弹起事件”，替换原指令，不要把新指令直接追加在旧 02 后面。每个按钮只在一个触摸事件中发送，避免按下和弹起各发送一次。控件的“发送键值”选项如已勾选，可取消以减少额外触摸报文。

首页 b_start：
```text
printh 55 01 00 00 ff ff ff
page game
```
首页 b_set：
```text
page settings
```
上一张/下一张：
```text
// 上一张 b_prev
printh 55 04 00 00 ff ff ff
// 下一张 b_next
printh 55 05 00 00 ff ff ff
```
两组分别放在对应按钮里，不要一起放到同一个按钮。比赛中翻图会被 FPGA 忽略。

比赛页 b_pulse 暂停：
```text
printh 55 06 00 00 ff ff ff
```
比赛页 b_continue 继续：
```text
printh 55 07 00 00 ff ff ff
```
比赛页 b_end 结束：
```text
printh 55 03 00 00 ff ff ff
page settle_battle
```
结算页 b_blue 蓝方：
```text
printh 55 20 00 00 ff ff ff
```
结算页 b_red 红方：
```text
printh 55 21 00 00 ff ff ff
```
结算页 b_100 百米：
```text
printh 55 22 00 00 ff ff ff
```
返回首页按钮 b_home：
```text
page home
```
目前赛果选择在 FPGA 轮播状态才接收；结束比赛后等待约 3 秒结束展示，再选赛果，提前选择不会排队。22 进入已有百米动画，不是八人成绩上传。

## E. 设置滑块、滤镜与恢复默认

滑块只在“触摸弹起事件”发送最终值。以亮度为例：
```text
n_bright.val=h_bright.val
printh 55 11
prints h_bright.val,1
printh 00 ff ff ff
```
其他滑块按相同三段发送方式修改：

| 滑块 | 数字 | CMD |
|---|---|---|
| h_sharp | n_sharp | 10 |
| h_bright | n_bright | 11 |
| h_contrast | n_contrast | 12 |
| h_saturation | n_saturation | 13 |
| h_volume | n_volume | 14 |

例如音量把上面 `n_bright/h_bright/11` 换成 `n_volume/h_volume/14`。拖动事件仅更新本地数字，不重复发送串口命令。当前部分事件原本已正确，请按此核对。

反色 bt_invert：
```text
printh 55 15
prints bt_invert.val,1
printh 00 ff ff ff
```
复古 bt_vintage：
```text
printh 55 16
prints bt_vintage.val,1
printh 00 ff ff ff
```
恢复默认 b_reset：
```text
printh 55 1f 00 00 ff ff ff
printh 55 30 01 00 ff ff ff
```
不要再只把两个滤镜按钮归零。FPGA 将回写全部默认值：锐度 1，亮度/对比度/饱和度 50，音量 63，两滤镜 0。百分比最后映射到 0–8 档，回写代表值会落在 0/13/25/38/50/63/75/88/100。

## F. 删除比赛页旧定时器代码

选中 game.tm0：把 en 属性改成 0，清空定时事件里原本“n_total.val=n_total.val+1”“满 60 秒停止”“写 t4/t3 时间”的整个逻辑。不要让屏幕与 FPGA 各自计时。

FPGA 会直接写 game.t4.txt、game.t3.txt 为 MM:SS，写 game.n_state.val 为状态码；不需要在屏幕再写接收解析程序。状态 6=运行、7=暂停、8=结束，其余准备和倒计时状态仍由 FPGA 管理。

原 j0 进度条假定比赛总时长 60 秒，目前没有确认的总时长协议。删除旧进度计算，并在后初始化加入 `vis j0,0` 隐藏，防止显示虚假的比赛进度。

## G. 编译、下载和验证

1. 保存 HMI，点击编辑器“编译”，逐项修复提示。确认工程选择的是实物 TJC8048X570 对应后缀，800×480。
2. 通过编辑器串口下载或按屏幕手册用 TFT 下载到屏幕。不要把 HMI 源文件当 TFT 烧录文件。
3. FPGA 保持当前匹配位流；具体文件与 SHA256 以当前 README.md 和 hmi/README.md 为准，本次屏端同步修复不需要重建 FPGA 位流。
4. 双向接线：屏 TX→D14，屏 RX←G11，GND 共地，接口应为 TTL。实际为 RS232 模式时须先转换。
5. 依次测首页状态、设置/恢复默认、开始/暂停/继续/结束，以及结束展示后蓝/红/百米选择。

首页 b_music 弹起事件必须改为 `printh 55 08 00 00 ff ff ff`，删除原 01 和 page game。t_m 回传有效 AUD 音乐数量 0–5。结算页返回首页按钮先发送 `printh 55 23 00 00 ff ff ff` 再执行 `page home`，即可退出 FPGA 赛果动画。t_flowing/t_title1 的 #文本上传不属于当前 55 协议，也未接入任意文字显示。这些限制见完整说明，不能用“串口已连通”推断所有输入框都已实现。