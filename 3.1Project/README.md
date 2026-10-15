# 双板 V3.1：启动恢复版

> **已知问题：高精度 RGB888 切图仍可能出现横向白条、短暂闪黑，自动轮播也可能异常，尚未解决。建议使用普通精度 RGB565。** 详见 [KNOWN_ISSUES.md](KNOWN_ISSUES.md)。

用户已上板确认本版启动卡住问题解决。保留单板频谱/波形移植、透明背景、音频修复开关、首首音乐就绪后的音画同步启动和 DLT 奖杯功能。

## 烧录

- A：`delivery/PHOTO_BOARD_A_720P_V3_1_BOOT_RECOVERY_LINK50M.bit`
- B：`delivery/PHOTO_BOARD_B_720P_V3_1_BOOT_AV_SYNC_LINK50M.bit`

已使用上述 B 板版本时，只需更新 A 板。新用户请使用发布包内配套的 A/B 位流。素材沿用现有 TF 卡及 `AWARD720.DLT`。

## 版本状态

启动回归已确认修复；高精度切图问题仍未解决。未交付中间失败的 LINK_FIX 位流。恢复说明与首错诊断见 [BOOT_RECOVERY.md](BOOT_RECOVERY.md)，当前位流与源码校验信息见 `delivery/delivery_manifest.json`。
