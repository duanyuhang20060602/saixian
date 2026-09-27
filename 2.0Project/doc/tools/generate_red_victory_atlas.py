#!/usr/bin/env python3
"""Generate the red winner's replacement glyphs without duplicating blue art.

The first 128 pixels of the title replace the corresponding blue title area.
Rows 96..127 hold the red team footer. Both use the same font/placement as
generate_victory_atlas.py and fit in one BRAM32K.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src/user_source/hdl_source"
FONT = Path("C:/Windows/Fonts/msyhbd.ttc")


def label(target, box, value, size):
    x, y, w, h = box
    tile = Image.new("L", (w * 3, h * 3))
    draw = ImageDraw.Draw(tile)
    font = ImageFont.truetype(str(FONT), size * 3)
    bounds = draw.textbbox((0, 0), value, font=font)
    draw.text(((w * 3 - bounds[2] + bounds[0]) // 2 - bounds[0],
               (h * 3 - bounds[3] + bounds[1]) // 2 - bounds[1]),
              value, font=font, fill=255)
    target.paste(tile.resize((w, h), Image.Resampling.LANCZOS), (x, y))


def main():
    whole_title = Image.new("L", (384, 96))
    label(whole_title, (0, 0, 384, 96), "红方获胜", 86)
    atlas = Image.new("L", (128, 128))
    atlas.paste(whole_title.crop((0, 0, 128, 96)), (0, 0))
    label(atlas, (0, 96, 128, 32), "RED / 红方战队", 15)
    words = []
    for y in range(128):
        for x in range(0, 128, 8):
            word = 0
            for dx in range(8):
                word = (word << 2) | min(3, (atlas.getpixel((x + dx, y)) + 42) // 85)
            words.append(word)
    mif = ["WIDTH=16;", "DEPTH=2048;", "ADDRESS_RADIX=HEX;",
           "DATA_RADIX=HEX;", "CONTENT BEGIN"]
    mif += [f"{i:03X} : {word:04X};" for i, word in enumerate(words)]
    mif += ["END;", ""]
    (OUT / "saixian_red_victory_atlas.mif").write_text("\n".join(mif), encoding="ascii")
    (OUT / "saixian_red_victory_atlas.hex").write_text(
        "".join(f"{word:04X}\n" for word in words), encoding="ascii")
    print(f"Generated {len(words)} words for red winner title/footer")


if __name__ == "__main__":
    main()
