"""Shared victory atlas plus a red-only title/footer patch; no full red copy."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'src/board_a/user_source/hdl_source'
FONT = 'C:/Windows/Fonts/msyhbd.ttc'

def label(image, box, text, size):
    x, y, w, h = box
    tile = Image.new('L', (w*3, h*3))
    draw = ImageDraw.Draw(tile)
    font = ImageFont.truetype(FONT, size*3)
    a, b, c, d = draw.textbbox((0, 0), text, font=font)
    draw.text(((w*3-c+a)//2-a, (h*3-d+b)//2-b), text, font=font, fill=255)
    image.paste(tile.resize((w, h), Image.Resampling.LANCZOS), (x, y))

def words(image, pixels):
    out = []
    for y in range(image.height):
        for x in range(0, image.width, pixels):
            value = 0
            for dx in range(pixels):
                value = (value << 2) | min(3, (image.getpixel((x+dx, y))+42)//85)
            out.append(value)
    return out

def save(name, data, width):
    (OUT / (name+'.hex')).write_text(''.join(f'{v:0{width//4}X}\n' for v in data))
    (OUT / (name+'.mif')).write_text(f'WIDTH={width};\nDEPTH={len(data)};\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+
        ''.join(f'{i:X} : {v:0{width//4}X};\n' for i, v in enumerate(data))+'END;\n')

blue = Image.new('L', (512, 128))
label(blue, (0, 0, 384, 96), '蓝方获胜', 86)
label(blue, (384, 0, 128, 24), 'VICTORY', 19)
label(blue, (384, 32, 128, 32), '对局结束', 27)
label(blue, (384, 64, 128, 24), '本局优胜', 18)
label(blue, (0, 96, 384, 32), 'BLUE ALLIANCE  /  蓝方战队', 16)
label(blue, (384, 96, 128, 32), '长按K4退出', 16)
data = words(blue, 16)
dictionary = list(dict.fromkeys(data))
assert len(dictionary) <= 1024
lookup = {v: i for i, v in enumerate(dictionary)}
indices = [lookup[v] for v in data]
low = [(indices[i] & 255) | ((indices[i+1] & 255) << 8) for i in range(0, 4096, 2)]
high = [sum((indices[i+j] >> 8) << (2*j) for j in range(8)) for i in range(0, 4096, 8)]
save('saixian_victory_atlas_index_lo', low, 16)
save('saixian_victory_atlas_index_hi', high, 16)
save('saixian_victory_atlas_dict', dictionary+[0]*(1024-len(dictionary)), 32)

red_title = Image.new('L', (512, 128))
label(red_title, (0, 0, 384, 96), '红方获胜', 86)
red = Image.new('L', (128, 128))
red.paste(red_title.crop((0, 0, 128, 96)), (0, 0))
label(red, (0, 96, 128, 32), '红方战队', 25)
save('saixian_red_victory_atlas', words(red, 8), 16)
print(json.dumps({'blue_unique_words': len(dictionary), 'red_patch_bits': 32768,
                  'shared_geometry': True, 'full_red_atlas_duplicated': False}, indent=2))
