# 串口文字实机测试记录

2026-10-31，用户反馈：
- SSCOM 发送完整 HEX 帧后，标题 TEST 更新成功。
- 底部轮播中文“欢迎使用串口修改文字”更新成功。
- 用户随后要求上传当前版本。

这是上述串口文字路径的实机反馈，未代表所有照片、音频、动画场景均完成实机回归。
原构建报告中的 hardware_validation=pending 为构建时记录，保留不改；本记录补充随后反馈。

## 使用

配套烧录下载包中的 PHOTO_BOARD_A.bit 和 PHOTO_BOARD_B.bit；GLYPHS.BIN 放 B 板 SD 卡。
A 板串口 115200、8N1、3.3V TTL。@0: 修改原标题，@1: 修改底部轮播；中文为 GB2312，每行最多16字符，末尾为实际 0D 0A。

SSCOM 勾选“16进制发送”，发送标题 TEST：

```
40 30 3A 54 45 53 54 0D 0A
```

底部轮播“欢迎使用串口修改文字”：

```
40 31 3A BB B6 D3 AD CA B9 D3 C3 B4 AE BF DA D0 DE B8 C4 CE C4 D7 D6 0D 0A
```

本版移除活动路径的 TITLE.BIN/TITLE2.BIN SXTTL 记录读取，复用原 SD 扫描与双板 UART 点阵传输。
GLYPHS.BIN 各512字节扇区带 SXGLYP01 头与组号，1121组，8964字形；无需 FAT 解析，可分散存放，但须位于原前1048576扇区（约512 MiB）扫描范围。
两个原文字区域独立更新和清空；断电后需重新输入，装载中再次发送的新行会丢弃。建议测试时每条间隔1秒。

A: 17500 LUT / 12397寄存器 / RAM9K 62 / RAM32K 15 / DSP27，setup/hold +0.281/+0.022 ns。
B: 15709 LUT / 10962寄存器 / RAM9K 64 / RAM32K 16 / DSP16，setup/hold +0.109/+0.022 ns。

下载 delivery-indexed-title-20261031.zip 获取配套bit、完整报告、工具、字库和源码补丁文件集。
