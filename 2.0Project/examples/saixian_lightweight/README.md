# 赛显轻量例程

这套例程针对 2.0 的帧缓冲转场、按键和数码管扫描。示例入口在 `saixian_light_demo.v`，直接实例化生产源码中的核心，避免另存一份实现后与正式工程漂移。它们已经用于本轮 2.0 改写，资源结论以整机布线报告为准。

| 例程 | 生产实现 | 要点 |
|---|---|---|
| `saixian_light_transition_demo` | `src/user_source/hdl_source/SD/frame_fifo_read.v` 内 `saixian_frame_mapper` | 六种效果、两种方向；先选基址和偏移，再用局部加减器及一个全地址加法器。无新增寄存延迟、RAM 或 DSP |
| `saixian_light_key_demo` | `src/user_source/hdl_source/saixian_key_debounce.v` | 两级输入同步，稳定计时后输出一拍按下脉冲；按配置周期推导计数位数。75MHz×20ms 用 21 位，不能误缩成 20 位 |
| `saixian_light_scan_demo` | `src/user_source/hdl_source/SD/seg_scan.v` | 六位扫描，保留原复位、位选和切换时刻；50MHz、200Hz 配置用 16 位定时器与 3 位位号 |

转场输入为当前像素 `x/y`、两个图像的行基址、偏移及模式。模式 0 为平移，1 为中间展开，2 为百叶窗，3 为斜向揭示，4 为块状溶解，5 为直接切换，6/7 保持原图。各行基址由外层控制器更新。算术保留原地址位宽下的回绕，未增加裁剪。

按键参数要求计算所得 `COUNT_MAX>=1`；扫描参数要求 `SCAN_COUNT>=0`。本轮没有修改按键长短按策略、20ms 消抖时长、视频/内存时钟和时序约束。

在 `2.0Project` 下验证：

```powershell
python tests/verify_light_examples.py --work E:/Codex/Work/saixian_light_examples_20261003/validation/recheck --baseline tests/reference/light_examples_20261003
.\tests\run_stability.ps1
.\build_saixian.ps1
```

对照基线为用户反馈实测良好的 2026-10-03 存储优化版，原文件在 `tests/reference/light_examples_20261003`。地址测试穷举所有有效平移列和偏移，另检查随机模式、边界及完整控制器输出；定时器测试包括 75MHz 下 20ms 消抖、抖动、释放及小周期参数。详细调研及最终资源记录见 `doc/赛显轻量例程与2.0优化_20261003.md`。
