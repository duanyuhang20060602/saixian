# 当前配套固件：分转场翻页音效版

本目录的 `PHOTO_BOARD_A_5_0.bit`、`PHOTO_BOARD_B_5_0.bit` 为最新验证通过的配套固件。它们与两个工程目录内的 `PHOTO_BOARD_A.bit`、`PHOTO_BOARD_B.bit` 分别完全一致。A、B 板必须一起更新。

固件源码提交：`c8041ec71b557f459c273afce12d3fbb33a3b549`。包含 11 种转场提示音及本轮资源优化，延迟优化尚未合入。两板最终布局布线与时序通过，35 项回归通过，实板听感验证待完成。

当前原始面积与时序报告已同步更新。文件 SHA256 见 [FX_PAGE_AUDIO_MANIFEST.json](FX_PAGE_AUDIO_MANIFEST.json)，完整分析见 [资源报告](../RESOURCE_REPORT_FX_PAGE_AUDIO.md)。

`origin_validation.json` 和 `verification/` 是原始版本的历史记录；当前固件的构建及回归记录位于 [fx_audio_results](../tests/fx_audio_results/)。

[配套 GitHub Release](https://github.com/duanyuhang20060602/saixian/releases/tag/v5.0-fx-page-audio-20261021) 中的 bit 与本目录一致。
