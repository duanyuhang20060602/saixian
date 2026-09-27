#!/usr/bin/env python3
"""Build the 512x256, 2bpp sprint-results ROM used by HDMI RTL.

Rows 0..7 are rank-ordered samples. Replace RUNNERS with official results
before using this display for a real race; lane is deliberately independent
from rank. Run this script from any directory.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src/user_source/hdl_source"
FONT = Path("C:/Windows/Fonts/msyhbd.ttc")
RUNNERS = [
    (4, "选手01", "10.23"),
    (5, "选手02", "10.31"),
    (3, "选手03", "10.38"),
    (6, "选手04", "10.46"),
    (2, "选手05", "10.55"),
    (7, "选手06", "10.63"),
    (1, "选手07", "10.76"),
    (8, "选手08", "10.91"),
]


def main():
    atlas = Image.new("L", (512, 256))

    def label(box, value, size):
        x, y, w, h = box
        tile = Image.new("L", (w * 3, h * 3))
        draw = ImageDraw.Draw(tile)
        font = ImageFont.truetype(str(FONT), size * 3)
        bounds = draw.textbbox((0, 0), value, font=font)
        draw.text(((w * 3 - bounds[2] + bounds[0]) // 2 - bounds[0],
                   (h * 3 - bounds[3] + bounds[1]) // 2 - bounds[1]),
                  value, font=font, fill=255)
        atlas.paste(tile.resize((w, h), Image.Resampling.LANCZOS), (x, y))

    for rank, (lane, name, mark) in enumerate(RUNNERS, 1):
        y = (rank - 1) * 28
        label((0, y, 50, 28), f"{rank:02}", 24)
        label((58, y, 80, 28), f"{lane} 道", 19)
        label((143, y, 190, 28), name, 20)
        label((370, y, 142, 28), f"{mark} 秒", 20)
    label((0, 224, 512, 32), "100 米决赛 · 最终排名", 27)

    words = []
    for y in range(256):
        for x in range(0, 512, 16):
            word = 0
            for dx in range(16):
                word = (word << 2) | min(3, (atlas.getpixel((x + dx, y)) + 42) // 85)
            words.append(word)
    mif = ["WIDTH=32;", "DEPTH=8192;", "ADDRESS_RADIX=HEX;",
           "DATA_RADIX=HEX;", "CONTENT BEGIN"]
    mif += [f"{i:04X} : {word:08X};" for i, word in enumerate(words)]
    mif += ["END;", ""]
    (OUT / "saixian_sprint_atlas.mif").write_text("\n".join(mif), encoding="ascii")
    (OUT / "saixian_sprint_atlas.hex").write_text(
        "".join(f"{word:08X}\n" for word in words), encoding="ascii")
    print(f"Generated {len(words)} words for eight sample runners")


if __name__ == "__main__":
    main()
