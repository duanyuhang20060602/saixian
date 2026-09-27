# TJC8048X570 屏幕工程快照

saixian_UART_HMI.HMI 是 2026-09-27 当前用户屏幕工程的归档副本，SHA256：54A957C58BE1A133200B858CF1F93E6388175E164F3129C4996058E05D560E60。

FPGA 对应固件：../src/td_project/HDMI1.4b_Transmitter_v2.0.bit；功能、时序和哈希见 ../doc/HMI_BUILD_STATUS.md。

本版本包含音乐数量回传、08 切歌、23 退出动画和既有双向参数/时间同步。home.b0、home.b1 的自定义文字发送和 FPGA 字库扩展未实现，屏幕中保留的文字输入控件不代表 FPGA 支持该功能。

此 HMI 未由 Codex 进行编辑器编译或生成 TFT，需按 ../doc/HMI_编辑器操作清单.md 和 ../doc/HMI_音乐与退出动画.md 核对属性与事件后编译、下载。HMI_CURRENT_EXTRACTED.json 是早先核对时的快照，其哈希与本次归档文件不同。
