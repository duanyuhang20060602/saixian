# 100 米结算背景（独立于五图轮播）

- 桌面交付文件：`C:\Users\39742\Desktop\SAIXIAN_100M_1280x720_24bit.bmp`
- 备选调亮版本：`C:\Users\39742\Desktop\SAIXIAN_100M_1280x720_24bit_bright.bmp`。用户目前决定继续使用原版；亮版仅留作备选，没有写入位流或 TF 卡。工程内另有 `100m_sprint_background_bright_preview.png` 预览。
- 工程内同名 BMP：1280×720、24 位、BI_RGB 无压缩，BMP 高度为正。
- `100m_sprint_background_preview.png` 是用户确认的画面预览。它基于 [Samuel Quek 的 Unsplash 跑道照片](https://unsplash.com/photos/athletes-race-on-a-track-during-a-competition-ybns3tTCoeE)生成；画面中的广告字样和标线经过生成式重绘，不能当作真实赛事现场的原样照片或官方赞助画面。

此 BMP 的标准 `biXPelsPerMeter`／`biYPelsPerMeter` 字段分别为 12345／54321，FPGA 用这组元数据识别专用背景；不要用图片编辑器重新另存 BMP，否则该标记可能丢失。其他五张普通 BMP 保持原样，继续作为轮播。

**不要把原版和调亮版同时放入 TF 卡**：两张都有专用标记，放入其中一张即可。调亮版可通过 `doc/tools/brighten_sprint_bmp.ps1` 从原版复现。

上卡时，TF 卡需要能被现有物理扇区扫描器找到这六张 BMP（五张轮播 + 本背景），必要时另有音频文件。扫描器不读 FAT 文件名，因此**文件名和拷贝顺序都不是识别依据**；旧 BMP 删除后残留的物理扇区仍可能被误扫描。请使用干净、备份过的专用 TF 卡，并在硬件上核对五图轮播、100 米背景和音频。当前 `doc/convert/sync_to_sd.py` 仍只处理最多五图且会清空卡，**不要用它准备本次六图卡**。本次没有写入或格式化 TF 卡。

HDL 只把带标记的 BMP 装入 SDRAM 第三帧缓冲（索引 2）；轮播继续使用索引 0／1。它们共享板上的 SD 控制器和 SDRAM 物理接口，但不会互相覆盖图像缓冲。背景不存在时，100 米结果页退回深色底。动画文字、成绩和排名仍由 FPGA 实时绘制，不烘焙进 BMP。
