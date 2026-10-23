"""Fill three unused menu glyphs; retain all existing ROM addresses and size."""
from pathlib import Path
import re
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]

def main():
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15)
    path = ROOT/'common/photo_menu_font.mif'
    text = path.read_text(encoding='utf-8')
    # Idempotent: only replace our three formerly unused glyph slots.
    text = re.sub(r'(?m)^7[CDE][0-9A-F] : [0-9A-F]+;\n', '', text)
    rows = []
    for glyph, char in enumerate('间隔秒', 124):
        im = Image.new('L', (16, 16), 0)
        draw = ImageDraw.Draw(im)
        left, top, right, bottom = draw.textbbox((0, 0), char, font=font)
        draw.text(((16-right+left)//2-left, (16-bottom+top)//2-top), char, font=font, fill=255)
        for row in range(16):
            value = sum(1 << (15-col) for col in range(16) if im.getpixel((col, row)) >= 96)
            if value:
                rows.append(f'{glyph*16+row:03X} : {value:04X};\n')
    text = text.replace('END;', ''.join(rows)+'END;')
    for p in [path, ROOT/'src/board_a/td_project/photo_menu_font.mif', ROOT/'src/board_b/td_project/photo_menu_font.mif']:
        p.write_text(text, encoding='utf-8')
    table = ROOT/'src/board_a/user_source/hdl_source/photo_menu_text_lookup'
    words = [int(v, 16) for v in table.with_suffix('.hex').read_text().split()]
    words[37*16:38*16] = [58, 59, 124, 125]+[0]*12
    table.with_suffix('.hex').write_text(''.join(f'{v:02X}\n' for v in words), encoding='utf-8')
    mif = 'WIDTH=8;\nDEPTH=1024;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'
    mif += ''.join(f'{i:03X} : {v:02X};\n' for i, v in enumerate(words))+'END;\n'
    for p in [table.with_suffix('.mif'), ROOT/'src/board_a/td_project/photo_menu_text_lookup.mif']:
        p.write_text(mif, encoding='utf-8')

if __name__ == '__main__':
    main()
