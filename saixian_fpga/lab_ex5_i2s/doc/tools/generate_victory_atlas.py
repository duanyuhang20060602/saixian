#!/usr/bin/env python3
"""Generate the blue-victory 2-bit antialiased type atlas (512 x 128).
Generated MIF is a project asset; HEX is used by the RTL simulation model.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src/user_source/hdl_source"
FONT = Path("C:/Windows/Fonts/msyhbd.ttc")

def main():
    atlas = Image.new("L", (512, 128))
    def label(box, value, size):
        x, y, w, h = box
        tile = Image.new("L", (w*3, h*3))
        draw = ImageDraw.Draw(tile)
        font = ImageFont.truetype(str(FONT), size*3)
        bounds = draw.textbbox((0, 0), value, font=font)
        draw.text(((w*3-bounds[2]+bounds[0])//2-bounds[0],
                   (h*3-bounds[3]+bounds[1])//2-bounds[1]),
                  value, font=font, fill=255)
        atlas.paste(tile.resize((w, h), Image.Resampling.LANCZOS), (x, y))
    label((0, 0, 384, 96), "蓝方获胜", 86)
    label((384, 0, 128, 24), "VICTORY", 19)
    label((384, 32, 128, 32), "对局结束", 27)
    label((384, 64, 128, 24), "本局优胜", 18)
    label((0, 96, 384, 32), "BLUE ALLIANCE  /  蓝方战队", 16)
    label((384, 96, 128, 32), "K2 返回轮播", 16)
    words = []
    for y in range(128):
        for x in range(0, 512, 16):
            value = 0
            for dx in range(16):
                shade = min(3, (atlas.getpixel((x+dx, y))+42)//85)
                value = (value << 2) | shade
            words.append(value)
    mif = ["WIDTH=32;", "DEPTH=4096;", "ADDRESS_RADIX=HEX;",
           "DATA_RADIX=HEX;", "CONTENT BEGIN"]
    mif += [f"{i:03X} : {v:08X};" for i, v in enumerate(words)]
    mif += ["END;", ""]
    (OUT/"saixian_victory_atlas.mif").write_text("\n".join(mif), encoding="ascii")
    (OUT/"saixian_victory_atlas.hex").write_text(
        "".join(f"{v:08X}\n" for v in words), encoding="ascii")
    atlas.save(ROOT/"doc/hmi_ui/blue_victory_type_atlas.png")
    print(f"Generated {len(words)} x 32-bit words; 512x128, 2bpp")
if __name__ == "__main__":
    main()

