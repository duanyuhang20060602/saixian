# 赛显单板赛事计分演示 · 2026-10-26

本目录保存 `SAIXIAN_MATCH_SINGLE_20261026.bit` 对应的源码快照，是独立单板比分版本。

目标板为 HX4S20C / EG4S20BG256，连接 HDMI_A；无需 TF 卡、串口屏或双板连接。

流程：选择双方 → 三秒开赛倒数 → 比分与计时 → 最后十秒提醒 → 胜负结果和二维金色奖杯 → 下一场。

| 阶段 | K1 | K2 | K3 | K4 |
| --- | --- | --- | --- | --- |
| 设置 | 选择主队 | 选择客队 | 30 秒／1／3／5 分钟 | 开始 |
| 比赛／暂停 | 短按加主队分，长按减分 | 短按加客队分，长按减分 | 暂停／继续 | 长按结束 |
| 结果 | — | — | — | 返回设置 |

长按约一秒。包含六支预设队伍、0～999 分、暂停修分、平局判定及 HDMI 提示音。
这不是 AB 双板版本，不包含照片轮播、音乐变调、串口屏或旋转浮雕奖杯。

## 源码与工程

- `project/src/user_source/hdl_source/match_control.v`：按键手势、比赛状态、比分与计时。
- `project/src/user_source/hdl_source/match_render.v`：比分、队名、计时及二维奖杯绘制。
- `project/src/user_source/hdl_source/match_top.v`：单板顶层、HDMI 和音频连接。
- `project/src/td_project/SAIXIAN_MATCH_SINGLE.al`：TD 工程。
- `project/src/user_source/constraints_source/`：管脚与时序约束。
- `tests/`：控制、按键、显示、视频接口及提示音测试。
- `delivery/manifest.json`：原固件 SHA256、完整构建输入哈希及验证摘要。
- [原版完整使用说明](使用说明.md)。

## 构建与验证

在本目录执行 `python -B tools/build.py`；原工具链为 TD 6.2.168116，脚本默认安装在 `D:/TD`。
直接打开已生成的 TD 工程即可，不需要运行 `prepare.py`。该准备脚本保留原件，重新生成时依赖原本地工程模板与 Windows 微软雅黑字体。

测试入口：`python -B tools/test_match.py`。需要 Pillow；Icarus 默认路径为 `D:/qiansai/.tools/iverilog-portable/ucrt64/bin`，可按安装位置修改脚本中的工具路径。
原验证摘要为五项仿真通过，建立／保持余量 +0.199／+0.022 ns；这是原构建记录，本次上传未重新综合，也未重新声明实板验收。

按照仓库协作约定，本次提交源码、构建脚本、验证摘要和预览图，未提交 `.bit`、TD 数据库、运行日志和仿真中间文件。
本地对应固件 SHA256：`c7a5b7fa321b4e64876c069cb0b33d0801bd688d639f7a7b566670084cb304de`。
原说明与清单中提及的固件、日志和时序报告属于本地交付件，未随本次源码提交上传；因此 `package.py` 需要先在本地重新构建并运行完整测试后使用。
