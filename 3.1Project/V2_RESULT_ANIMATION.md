# V2.0 赛果动画移植

板 A 复用 V2.0 的百米成绩、八人排名和前三领奖台渲染逻辑及压缩字库图集。动画合成在 HDMI 最终像素路径上，保持原照片/音频处理模块不变。当前 AV_B_WINNERS 版本已恢复蓝方和红方获胜场景。A 音频缓冲减至 4096，FFT/波形分析移到 B，为图集释放 RAM；红方仅增加 32 Kbit 差异文字补丁，两队共用渲染器。

## 操作

赛果动画播放期间：KEY2 选择蓝方获胜、KEY3 选择红方获胜，长按 KEY4 退出。HMI 可直接发送 `55 20 00 00 FF FF FF`（蓝方）或 `55 21 00 00 FF FF FF`（红方）。

在照片轮播界面长按 KEY4（约 1 秒）即可启动百米赛果；动画播放时再次长按 KEY4 可退出。KEY1 可推进动画阶段。KEY4 短按仍保留奖杯功能。

串口屏也沿用既有协议：`55 22 00 00 FF FF FF` 播放百米赛果，`55 23 00 00 FF FF FF` 退出动画。百米赛果会自动播放排名及领奖台。

先在图片轮播中选好背景照片，再从屏幕选择赛果。百米赛道背景见 `delivery/SAIXIAN_100M_1280x720_24bit.bmp`，请放到 B 板 TF 卡的普通照片集中并先切换到该图。照片最多 6 张；若卡上已满，请用这张背景替换一张普通照片。V2.0 动画中的运动员姓名和成绩是演示内容；当前没有八人成绩录入或真实成绩计算接口。

## 工程文件

- `common/saixian_battle_result_fx_pipelined.v`：动画状态机、绘制器和压缩字库 ROM。
- `projects/board_a/src/user_source/hdl_source/saixian_sprint_atlas*.mif`：板 A 推断 BRAM 初始化文件。
- `projects/board_a/src/user_source/hdl_source/saixian_sprint_atlas*.hex`：仿真字库文件。
- `delivery/SAIXIAN_100M_1280x720_24bit.bmp`：可选百米赛道背景照片。

RGB888 的板上图像切换仍需复验；本次动画移植本身不作为高精度切图问题已解决的实板证据。

完整配套烧录和资源迁移说明见 [AV_B_WINNERS](delivery/AV_B_WINNERS_README.md)。本版没有流体效果，原百米排名和领奖台保留。
