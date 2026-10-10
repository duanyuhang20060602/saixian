# 双板 FPGA 图片传输代码：B → A，1366×768 / 60 Hz

**这是两块 HX4S20 / EG4S20BG256 的双板工程。重点是 B 板发送、A 板接收、握手和帧缓存传输代码。**
HDMI 接 A 板，SD 卡仅接 B 板。两份板卡 bit 不能互换。

## 已实测的状态（2026-10-10）

| 路径 | 结果 |
|---|---|
| A 板本地产生 1366×768 / 60 Hz 图案 | 用户确认正常 |
| B 板内置图 → 板间链路 → A 板 SDRAM → HDMI | 用户确认正常，两板最终数字 5 |
| B 板 SD 图片 → 缩放 / SDRAM → A 板 HDMI | 可显示，仍有固定纹波 / 边界异常，未完成验收 |

此前绿色异常在修改板间接线后消失。内置图链路正常后，SD 图片问题的排查重点
缩小到 B 板的 SD 读取、BMP 解码、缩放、SDRAM 写入与回读。**尚未确定是哪一级出错，
不能把本分支的 SD 版本标注为已经修复。**

## 优先阅读：板间传输代码

- [传输协议、引脚与状态说明](TRANSFER.md)
- [B 板内置图发送顶层](projects/board_b_builtin_sender/src/user_source/hdl_source/top_builtin_diagnostic.v)：
  实测通过的基准，下降沿更新数据，上升沿按 ready 接受推进。
- [B 板 SDRAM 图片发送状态机](projects/board_b_sd_sender/src/user_source/hdl_source/link_sender.v)：
  读请求、ACK 退回、FIFO 取字、等待注册输出、高低像素发送、暂停保持。
- [A 板接收状态机](projects/board_a_receiver/src/user_source/hdl_source/dual_still_link_rx.v)：
  请求写帧、等待 FIFO 清零握手结束、检查 SOF/EOF 和像素数量、双像素打包、整帧确认。
- [A 板接收显示顶层](projects/board_a_receiver/src/user_source/hdl_source/top_board_a.v)：
  整帧确认和显示启动、SDRAM、跨时钟域同步与数码管。
- [B 板 SD 发送顶层](projects/board_b_sd_sender/src/user_source/hdl_source/top_board_b.v)：
  SD 读图 / 缩放 → RGB565 打包 → B SDRAM → 传输，保留供后续定位。

## bit 流：推荐先运行已通过的内置图双板路径

| 板卡 | 文件 | 用途 |
|---|---|---|
| **A** | [BOARD_A_1366X768_60HZ_SD_LINK.bit](bitstreams/BOARD_A_1366X768_60HZ_SD_LINK.bit) | 接收 B 图片，存入 A SDRAM，HDMI 输出；两种 B 版本共用 |
| **B，内置图基准** | [BOARD_B_BUILTIN_1366X768_LINK_DIAGNOSTIC.bit](bitstreams/BOARD_B_BUILTIN_1366X768_LINK_DIAGNOSTIC.bit) | 无需 SD 卡，用户确认双板路径正常 |
| **B，SD 图片实验** | [BOARD_B_1366X768_60HZ_SD_LINK.bit](bitstreams/BOARD_B_1366X768_60HZ_SD_LINK.bit) | SD 图片读取及缩放，保留待修复版本 |

先配置并启动 A，再配置 / 启动 B。更换图片或重试时重新启动两板。
内置图版没有 B 板 SDRAM 或 SD 读取，输出原生彩条、渐变、棋盘格和细线。
底部细线本身属于测试图案。

## 工程与构建

三个工程完全独立，源文件和引脚约束位于 `projects/<工程名>/src`。
目标器件 EG4S20BG256，使用 Anlogic Tang Dynasty 6.2.1。

1. 运行 `python tools/configure_projects.py`，将 TD 工程 Path 更新为本次克隆的路径。
2. 在目标工程 `src/td_project` 中打开 `.al` 文件，或运行 TD 命令行：

```powershell
& "C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe" build_board.tcl
```

若 TD 安装位置不同，在当前终端设置 `SAIXIAN_TD_ROOT` 为安装根目录。
bitstreams 中是本次实测所用构建的副本；重新构建会改变布局、bit 和 SHA256。
不要求重建结果与已发布 bit 字节一致。

## 图片格式

SD 实验版沿用 raw-sector BMP 扫描，没有 FAT 文件系统解析：
24 位、未压缩、正高度 BMP，宽 640–1920、高 360–1080。
缩放输出 1366×768，铺满画面；原生尺寸直接通过。
文件必须连续存放并从扇区边界开始，建议制作从扇区 0 开始的镜像。

```powershell
python tools/prepare_sd_image.py --bmp "D:\pictures\photo.bmp" --output "D:\pictures\photo.raw"
```

脚本只生成文件，不访问实体 SD 卡。镜像需用户使用磁盘镜像工具写入整个备用卡，
这会覆盖卡中原有分区和文件。制卡步骤与 SD 路径异常无修复关系。

## 构建证据与限制

三份 bit 的最终路由建立/保持时序通过，余量、文件大小和 SHA256 见
[delivery_manifest.json](delivery_manifest.json)。
数字验证曾覆盖完整帧发送/接收、ready 暂停、RGB565、帧缓存回读、AVI 校验和与 BCH、
连续两个 HDMI 帧。功能路径中的 PLL、SD 源和 SDRAM 应用接口使用行为模型；
这些检查不证明实际 SD SPI 或 SDRAM 电气时序正确。
本目录仅保留可构建工程、选定 bit 和文档，不包含 TD 临时数据库或大批仿真缓存。
板间协议当前**没有 CRC**，数字 5 表示帧流程完成，不能证明所有像素无误码。
