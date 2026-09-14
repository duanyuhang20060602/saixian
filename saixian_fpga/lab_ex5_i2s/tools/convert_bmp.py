#!/usr/bin/env python3
"""Convert an image to the exact BMP format consumed by Saixian."""
from __future__ import annotations
import argparse
from pathlib import Path
from PIL import Image, ImageOps

def main() -> int:
    ap = argparse.ArgumentParser(description="转换为 640x480、24 位、非压缩 BMP")
    ap.add_argument("source", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--fit", choices=("crop", "contain"), default="crop")
    ap.add_argument("--background", choices=("black", "white"), default="black")
    args = ap.parse_args()
    with Image.open(args.source) as im:
        im = im.convert("RGB")
        if args.fit == "crop":
            im = ImageOps.fit(im, (640, 480), method=Image.Resampling.LANCZOS)
        else:
            im.thumbnail((640, 480), Image.Resampling.LANCZOS)
            canvas = Image.new("RGB", (640, 480), args.background)
            canvas.paste(im, ((640-im.width)//2, (480-im.height)//2))
            im = canvas
        args.output.parent.mkdir(parents=True, exist_ok=True)
        im.save(args.output, format="BMP", bits=24)
    print(args.output)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
