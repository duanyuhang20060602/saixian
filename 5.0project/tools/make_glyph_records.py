"""Convert c4's FONTS.BIN to sector records, writing ordinary files only."""
from pathlib import Path
import argparse,struct
MAGIC=b'SXGLYP01'
def convert(source):
    if source[:8]!=b'SXFONT01' or len(source)<512+8964*32:raise ValueError('Expected c4 SXFONT01 GB2312 font library')
    records=bytearray()
    for group in range(1121):
        payload=source[512+group*256:512+min((group+1)*256,8964*32)].ljust(256,b'\0')
        records.extend((MAGIC+struct.pack('<HBBI',group,1,8,0)+payload).ljust(512,b'\0'))
    return bytes(records)
def main():
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('--out',type=Path,default=Path('GLYPHS.BIN'));a=p.parse_args()
    result=convert(a.source.read_bytes())
    if a.out.exists():
        old=a.out.read_bytes()
        if len(old)!=len(result) or any(old[i:i+8]!=MAGIC for i in range(0,len(old),512)):raise ValueError('Existing output is not a glyph-record library; use a new output path')
        with a.out.open('r+b') as f:f.write(result);f.flush()
    else:a.out.write_bytes(result)
    print(f'Created {a.out}: {len(result)} bytes, 1121 sector records; glyph pixels unchanged')
if __name__=='__main__':main()
