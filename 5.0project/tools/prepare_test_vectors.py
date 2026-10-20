from pathlib import Path
import zlib
ROOT=Path(__file__).resolve().parents[1]
vectors=[]
for image in range(6):
    pixels=[((p*0x1237)^(0x8291+image*0x317)) & 65535 for p in range(32)]
    payload=b''.join(p.to_bytes(2,'big') for p in pixels)
    vectors.append(f'{zlib.crc32(payload):08x}')
(ROOT/'tests/crc_reference.hex').write_text('\n'.join(vectors)+'\n',encoding='ascii')
(ROOT/'tests/pattern_crc_reference.hex').write_text(f"{zlib.crc32(b''.join((((p*0x1237)^0x8291)&65535).to_bytes(2,'big') for p in range(4096))):08x}\n",encoding='ascii')
