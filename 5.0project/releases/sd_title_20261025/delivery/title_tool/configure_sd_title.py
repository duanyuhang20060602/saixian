"""Compile one shared title to two checksummed SD scan records (no FPGA rebuild)."""
from pathlib import Path
import argparse, os, struct, zlib

MAGIC = b'SXTTL001'
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

def write_title_file(output, data):
    output = Path(output)
    if output.exists():
        old = output.read_bytes()
        if len(old) != 1024 or old[:8] != MAGIC or old[512:520] != MAGIC:
            raise ValueError('Existing output is not a title configuration. Choose a new file name.')
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
    ap.add_argument('--output', type=Path)
    ap.add_argument('--font', type=Path, default=Path('C:/Windows/Fonts/msyh.ttc'))
    args = ap.parse_args()
    if args.text is None and args.text_file is None:
        import tkinter as tk
        from tkinter import simpledialog, filedialog, messagebox
        root = tk.Tk(); root.withdraw()
        text = simpledialog.askstring('SD 卡题目设置', '请输入题目（1～16 个字）：', initialvalue='100米', parent=root)
        if text is None:
            return
        output = filedialog.asksaveasfilename(parent=root, initialfile='TITLE.BIN', defaultextension='.BIN')
        if not output:
            return
        try:
            data, _ = compile_title(text, args.font)
            write_title_file(output, data)
        except (ValueError, OSError) as exc:
            messagebox.showerror('SD title', str(exc), parent=root)
            return
        messagebox.showinfo('SD 卡题目设置', '配置已生成。后续请直接选择 SD 卡上的同一个 TITLE.BIN 更新，然后重启两块板。', parent=root)
    else:
        text = args.text if args.text is not None else args.text_file.read_text(encoding='utf-8-sig').rstrip('\r\n')
        data, _ = compile_title(text, args.font)
        output = args.output or Path('TITLE.BIN')
        write_title_file(output, data)
        print(f'{output}: {len(text)} characters, {len(data)} bytes')

if __name__ == '__main__':
    main()
