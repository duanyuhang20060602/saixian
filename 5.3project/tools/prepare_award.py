"""Convert the exact tagged single-board plate to a lossless native BMP.

No image-library color conversion: every RGB565 word must round-trip exactly.
The reserved BMP bytes SXAW identify this asset; ordinary BMPs stay photos.
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parents[1]

def prepare(source, output):
    raw = source.read_bytes()
    assert len(raw) == 1280 * 720 * 2
    pixels = struct.unpack('<921600H', raw)
    payload = bytearray()
    reconstructed = bytearray(len(raw))
    for y in range(719, -1, -1):
        for x in range(1280):
            p = pixels[y * 1280 + x]
            r, g, b = (p >> 11) & 31, (p >> 5) & 63, p & 31
            r, g, b = (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)
            payload.extend((b, g, r))
            struct.pack_into('<H', reconstructed, (y * 1280 + x) * 2,
                             ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3))
    assert reconstructed == raw
    header = bytearray(54)
    struct.pack_into('<2sI4sI', header, 0, b'BM', 54 + len(payload), b'SXAW', 54)
    struct.pack_into('<IiiHHIIiiII', header, 14, 40, 1280, 720, 1, 24, 0,
                     len(payload), 2835, 2835, 0, 0)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(header + payload)
    report = dict(format='native bottom-up 24-bit BMP; reserved bytes SXAW',
                  width=1280, height=720, bytes=output.stat().st_size,
                  tagged_plate_sha256=hashlib.sha256(raw).hexdigest(),
                  bmp_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                  exact_rgb565_round_trip=True, color_modes=['RGB565', 'RGB888'],
                  directory_limit='Award occupies one of the first six discovered BMP entries')
    output.with_suffix('.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('source', type=Path)
    p.add_argument('--output', type=Path, default=ROOT / 'award_media/AWARD720.BMP')
    a = p.parse_args()
    prepare(a.source, a.output)
