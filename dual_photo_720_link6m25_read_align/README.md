# 2.0 Photo 双板 720p：A读数据对齐阶段快照

> **实板状态（2026-10-12）：720p版本已修复，用户确认。此前误将768p图片当作720p测试图，现已撤回“仍有相同纹波”的判断。**
>
> 输出为1280×720。本套A/B bit和源码对应；原始1366×768目标尚未完成。

目的：比较原 2.0 的 640 字行跨度和视频时钟条件，定位 1366×768 双板固定纹波。独立工程，1366 工程及旧 bit 均保留。

## 烧录文件

- A：`delivery/PHOTO_BOARD_A_1280X720_J2_NOCRC_NOENHANCE_LINK6M25_A_READ_ALIGN.bit`
- B：`delivery/PHOTO_BOARD_B_1280X720_J2_NOCRC_NOENHANCE_LINK6M25_A_READ_ALIGN.bit`
- 源码与匹配 bit：`delivery/DUAL_PHOTO_1280X720_J2_NOCRC_NOENHANCE_LINK6M25_A_READ_ALIGN_SOURCE_AND_BITS.zip`

**两板必须同时使用本套 720p bit。不能混用 1366、CRC_DIAG、QUADWRITE 或 B_PATTERN。**

## 对照条件

- 输出 1280×720，RGB565。每行 640 个 32 位字，每帧 460800 字；三个槽基地址 0、460800、921600。
- A、B 的 `frame_fifo_read.v`、`frame_fifo_write.v`、`frame_read_write.v` 逐文件恢复 photo release d23efef 原版。
- A 视频 PLL 直接使用 2.0 原版：像素 75MHz、串行 375MHz。水平总长 1650、垂直总长 750，实际约 60.61Hz；AVI 标记 VIC4。
- SD、BMP 解析和原缩放算法沿用 photo release，输出改回原 1280×720；640×480 清晰缩放特例保留。原 SD 卡六张图可以继续使用。
- 三槽缓存、邻图预读、板间控制与显示包装仍是双板实现；本工程不是整个单板 2.0 的逐文件副本。
- 板间仍为 16 位、6.25MHz、原 HIGH/LOW 时序，图片 CRC32 关闭；UART 包 CRC16 保留。没有 QUADWRITE 动态掩码或填充写入。
- 增强和锐化在 A 顶层固定为 0，设置操作不能开启；保持原 21 拍显示延迟，亮度、对比度、饱和度及转场保留。KEY1 上一张、KEY4 下一张、KEY3 设置，六图手动循环。

## 接线

继续使用当前 J2，同号脚连接：数据 1—10/13—18，时钟 19、valid20、SOF21、EOF22、ready23、image_ack24；控制 UART 25/26，共地 12 或 30。A J2-25 为 TX、J2-26 为 RX，B 角色相反。串口屏仍接 A J1-1/D14、J1-2/G11；HDMI 接 A，SD 卡接 B。没有新增线。

## 实板比较步骤

1. 两板烧录本套 bit，用当前相同 SD 卡、线缆和显示器启动。
2. 先观察切换结束后的静态纹波测试图，记录是否还有固定毛刺；1366 图片会缩放成 1280，细密棋盘的插值变化应与固定错位区别。
3. 比较色块边界、横线、上下方向，再检查六张图片和快速切图。
4. 若 720 正常，1366 分辨率/行地址/时钟适配是下一步重点；若仍异常，继续定位 B 读回、板间交付和 A 接收。

原 720p 对照版能正常切图但有局部横带，本版用于检查显示处理是否参与纹波。本版720p实板纹波问题已修复（用户确认）。仿真和 STA 通过不等于毛刺已消除，底层加密 SDRAM 核未进入应用模型仿真。

## 构建

`python tools/run_tests.py --only tb_real_fifo_link tb_real_fifo_link_delay tb_no_crc_system_async tb_render`

随后在本目录运行 `./build.ps1`。TD 路径可用 SAIXIAN_TD_ROOT 指定。release 工具检查参与构建源码 SHA256、bit 时间戳和建立/保持时序。VALIDATION.md、delivery_manifest.json 保存最终证据。

板间流程检查见 [FLOW_REVIEW.md](FLOW_REVIEW.md)。

## 时钟对照

从NOENHANCE 12.5MHz版本复制建立独立工程，仅更改B的板间PLL和A的外部接收时钟约束。PLL外部反馈50MHz/8=6.25MHz，CLKC0_DIV=80保持VCO500MHz；A link_clk周期160ns，上升/下降沿相隔80ns。B SDC derive_clocks从实际PLL推导新频率。UART仍115200，SD100MHz、SDRAM50MHz、视频75MHz均保持。

请两板使用本套bit，以相同接线及图片比较纹波是否减轻、消失或位置改变。此次不合入刷新控制修改。降速也会降低SDRAM读写压力，改善不能单独证明线缆是根因。

## A板读数据对齐迁移版
本版恢复真实SD卡、六图缓存、板间传输、按键/HMI切图和转场。仅A板SDRAM读数据延迟一拍，valid不延迟；所有其他RTL与LINK6M25版相同。B板尚无地址编码实板证据证明需要同样修正，本次保持其逻辑不变以单独验证A板修正。
两板烧录本套文件；SD接B、HDMI接A、沿用原J2接线。增强/锐化和帧CRC继续关闭。支持原SD素材；优先用原生1280x720_纹波测试.bmp比较，避免缩放混叠影响判断。
地址编码对齐诊断在A板实板显示500011，为本次迁移依据；该结果不等同本双板图片版验收。此次720p先验证，1366x768还有683字行跨度/四字组对齐问题，尚未迁回。
请检查静态纹波及六图首尾循环、上一张/下一张、快速换方向；建议连续手动切换100次。实板反馈已更正：720p版本已修复，此前混淆了768p与720p测试图片。
