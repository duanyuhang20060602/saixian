#!/usr/bin/env python3
"""Validate BMP assets against the current Saixian FPGA parser."""
from __future__ import annotations
import argparse
import struct
from pathlib import Path

MIN_W, MIN_H = 1280, 720
MAX_W, MAX_H = 1920, 1080
MAX_FILE_SIZE = 8_388_608


def validate(path: Path) -> list[str]:
    problems: list[str] = []
    raw = path.read_bytes()
    if len(raw) < 54:
        return ["文件短于54字节BMP头"]
    sig = raw[:2]
    file_size = struct.unpack_from("<I", raw, 2)[0]
    pixel_offset = struct.unpack_from("<I", raw, 10)[0]
    dib_size, width, height = struct.unpack_from("<Iii", raw, 14)
    planes, bpp = struct.unpack_from("<HH", raw, 26)
    compression = struct.unpack_from("<I", raw, 30)[0]
    if sig != b"BM": problems.append("签名不是BM")
    if dib_size < 40: problems.append(f"DIB头过短: {dib_size}")
    if not (MIN_W <= width <= MAX_W and MIN_H <= height <= MAX_H):
        problems.append(f"尺寸{width}x{height}超出{MIN_W}x{MIN_H}至{MAX_W}x{MAX_H}正高度范围")
    if planes != 1: problems.append(f"颜色平面数为{planes}，要求1")
    if bpp != 24: problems.append(f"位深为{bpp}，要求24")
    if compression != 0: problems.append(f"压缩字段为{compression}，要求BI_RGB(0)")
    if pixel_offset < 54 or pixel_offset >= len(raw): problems.append(f"像素偏移异常: {pixel_offset}")
    if file_size == 0 or file_size > MAX_FILE_SIZE: problems.append(f"BMP文件长度字段异常: {file_size}")
    if file_size > len(raw): problems.append("BMP头中的文件长度超过实际长度")
    if width > 0 and height > 0:
        row_stride = (width * 3 + 3) & ~3
        if pixel_offset + row_stride * height > len(raw): problems.append("像素数据被截断")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description="检查赛显24-bit/BI_RGB BMP")
    ap.add_argument("paths", nargs="+", type=Path)
    args = ap.parse_args()
    failed = False
    for item in args.paths:
        paths = sorted(item.glob("*.bmp")) if item.is_dir() else [item]
        if not paths:
            print(f"FAIL {item}: 没有BMP")
            failed = True
        for path in paths:
            try:
                problems = validate(path)
            except OSError as exc:
                problems = [str(exc)]
            if problems:
                failed = True
                print(f"FAIL {path}: " + "；".join(problems))
            else:
                print(f"OK   {path}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
