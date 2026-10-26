"""Generate independent top-left title and bottom ticker SD font records."""
from pathlib import Path
import argparse, os, struct, zlib

MAGIC = b'SXTTL001'
INDEPENDENT_MAGIC = b'SXTTL002'
MAX_CHARACTERS = 16

def compile_title(text, font_path):
    from PIL import Image, ImageDraw, ImageFont
    if not 1 <= len(text) <= MAX_CHARACTERS:
        raise ValueError('Title must contain 1 to 16 characters; it is never truncated.')
    if any(ord(ch) < 32 or 0xD800 <= ord(ch) <= 0xDFFF for ch in text):
        raise ValueError('Control characters and unpaired surrogates are not supported.')
    font = ImageFont.truetype(str(font_path), 15)
    rows = bytearray()
    for ch in text.ljust(MAX_CHARACTERS):
        image = Image.new('1', (16, 16))
        draw = ImageDraw.Draw(image)
        left, top, right, bottom = draw.textbbox((0, 0), ch, font=font)
        if right-left > 16 or bottom-top > 16:
            raise ValueError('The selected font does not fit a 16 x 16 cell.')
        draw.text(((16-right+left)//2-left, (16-bottom+top)//2-top), ch, font=font, fill=1)
        for y in range(16):
            row = sum(int(bool(image.getpixel((x, y)))) << (15-x) for x in range(16))
            rows.extend(struct.pack('>H', row))
    identity = zlib.crc32(bytes([len(text)]) + rows)
    result = bytearray()
    for part in range(2):
        fields = bytes([len(text), part, 1, 0]) + struct.pack('>I', identity)
        payload = rows[part*256:(part+1)*256]
        crc = zlib.crc32(fields + payload)
        record = MAGIC + fields + struct.pack('>I', crc) + payload
        result.extend(record.ljust(512, b'\0'))
    return bytes(result), bytes(rows)

def compile_texts(title, ticker, font_path):
    """Four sector-aligned records, one identity for both independent banks."""
    _, title_rows = compile_title(title, font_path)
    _, ticker_rows = compile_title(ticker, font_path)
    rows = title_rows + ticker_rows
    lengths = (len(title), len(ticker))
    identity = zlib.crc32(bytes(lengths) + rows)
    result = bytearray()
    for part in range(4):
        fields = bytes([lengths[part // 2], part, 2, 0]) + struct.pack('>I', identity)
        payload = rows[part * 256:(part + 1) * 256]
        crc = zlib.crc32(fields + payload)
        result.extend((INDEPENDENT_MAGIC + fields + struct.pack('>I', crc) + payload).ljust(512, b'\0'))
    return bytes(result), rows

def write_title_file(output, data):
    output = Path(output)
    if output.exists():
        old = output.read_bytes()
        expected = INDEPENDENT_MAGIC if len(data) == 2048 else MAGIC
        if len(old) != len(data) or any(old[i:i+8] != expected for i in range(0, len(old), 512)):
            raise ValueError('Existing output has a different format. Keep the old file and choose TITLE2.BIN for the independent texts.')
        # Preserve the existing allocation: a raw scan must not rediscover an
        # orphaned copy created by truncating/replacing a FAT file.
        with output.open('r+b') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
    else:
        with output.open('xb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    choice = ap.add_mutually_exclusive_group()
    choice.add_argument('--text')
    choice.add_argument('--text-file', type=Path)
    ap.add_argument('--title', help='Independent title, 1 to 16 characters')
    ap.add_argument('--ticker', help='Independent scrolling text, 1 to 16 characters')
    ap.add_argument('--output', type=Path)
    ap.add_argument('--font', type=Path, default=Path('C:/Windows/Fonts/msyh.ttc'))
    args = ap.parse_args()
    if args.title is not None or args.ticker is not None:
        if args.title is None or args.ticker is None or args.text is not None or args.text_file is not None:
            ap.error('Provide both --title and --ticker; do not combine with legacy --text options.')
        data, _ = compile_texts(args.title, args.ticker, args.font)
        output = args.output or Path('TITLE2.BIN')
        write_title_file(output, data)
        print(f'{output}: independent title {len(args.title)} / ticker {len(args.ticker)}, {len(data)} bytes')
    elif args.text is None and args.text_file is None:
        import tkinter as tk
        from tkinter import simpledialog, filedialog, messagebox
        root = tk.Tk(); root.withdraw()
        title = simpledialog.askstring('SD 卡文字设置', '左上角标题（1～16 个字）：\n请输入你要显示的新标题。', initialvalue='标题测试', parent=root)
        if title is None:
            return
        ticker = simpledialog.askstring('SD 卡文字设置', '底部滚动文字（1～16 个字）：', initialvalue='底部独立文字', parent=root)
        if ticker is None:
            return
        output = filedialog.asksaveasfilename(parent=root, initialfile='TITLE2.BIN', defaultextension='.BIN')
        if not output:
            return
        try:
            data, _ = compile_texts(title, ticker, args.font)
            write_title_file(output, data)
        except (ValueError, OSError) as exc:
            messagebox.showerror('SD title', str(exc), parent=root)
            return
        messagebox.showinfo('SD 卡文字设置',
            f'已保存：{output}\n\n左上角标题：{title}\n底部滚动文字：{ticker}\n\n'
            '请确认保存到 B 板 SD 卡上的同一个 TITLE2.BIN，再将两块板一起断电重启。\n'
            '使用原示例的“100米”会与默认标题相同，看不出变化。', parent=root)
    else:
        text = args.text if args.text is not None else args.text_file.read_text(encoding='utf-8-sig').rstrip('\r\n')
        data, _ = compile_title(text, args.font)
        output = args.output or Path('TITLE.BIN')
        write_title_file(output, data)
        print(f'{output}: {len(text)} characters, {len(data)} bytes')

if __name__ == '__main__':
    main()
