import struct
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).parents[1] / "tools"))
from validate_bmp import validate

def make_bmp(path: Path, width=1280, height=720, bpp=24, compression=0, truncate=False):
    pixels = b"\0" * (max(width, 1) * max(abs(height), 1) * max(bpp // 8, 1))
    header = bytearray(54)
    header[:2] = b"BM"
    struct.pack_into("<I", header, 2, 54 + len(pixels))
    struct.pack_into("<I", header, 10, 54)
    struct.pack_into("<IiiHHI", header, 14, 40, width, height, 1, bpp, compression)
    path.write_bytes(header + (pixels[:-10] if truncate else pixels))

class ValidateBmpTests(unittest.TestCase):
    def test_valid(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"ok.bmp"; make_bmp(p); self.assertEqual(validate(p), [])
    def test_wrong_variants(self):
        with tempfile.TemporaryDirectory() as d:
            d=Path(d)
            for name,kw in [("size",{"width":640,"height":480}),("bpp",{"bpp":32}),("zip",{"compression":1}),("cut",{"truncate":True})]:
                p=d/f"{name}.bmp"; make_bmp(p,**kw); self.assertTrue(validate(p),name)

if __name__ == "__main__": unittest.main()
