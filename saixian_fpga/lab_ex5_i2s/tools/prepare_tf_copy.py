#!/usr/bin/env python3
"""Copy up to five already-valid BMPs to an explicitly named removable drive."""
from __future__ import annotations
import argparse
import ctypes
import shutil
from pathlib import Path
from validate_bmp import validate

DRIVE_REMOVABLE = 2

def main() -> int:
    ap = argparse.ArgumentParser(description="安全复制赛显 BMP；不格式化、不删除文件")
    ap.add_argument("source_dir", type=Path)
    ap.add_argument("target_root", type=Path, help="必须明确写盘符根目录，例如 F:\\")
    args = ap.parse_args()
    target = args.target_root.resolve()
    if target.parent != target or len(target.drive) != 2:
        raise SystemExit("拒绝：target_root 必须是明确的 Windows 盘符根目录")
    if ctypes.windll.kernel32.GetDriveTypeW(str(target)) != DRIVE_REMOVABLE:
        raise SystemExit(f"拒绝：{target} 未被 Windows 识别为可移动盘")
    files = sorted(args.source_dir.glob("*.bmp"))
    if not 1 <= len(files) <= 5:
        raise SystemExit("源目录必须包含 1 到 5 张 BMP")
    for src in files:
        problems = validate(src)
        if problems: raise SystemExit(f"{src.name}: " + "；".join(problems))
    for index, src in enumerate(files, 1):
        dst = target / f"SAIXIAN{index}.BMP"
        if dst.exists(): raise SystemExit(f"拒绝覆盖已有文件：{dst}")
        shutil.copy2(src, dst)
        print(f"COPIED {src} -> {dst}")
    print("复制完成。请使用 Windows 的安全弹出后再拔卡。")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
