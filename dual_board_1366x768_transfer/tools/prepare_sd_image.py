"""Create a raw-sector SD image; never access or modify a physical drive."""
from pathlib import Path
import argparse
import struct

def validate(data):
    if len(data)<54 or data[:2]!=b'BM':raise ValueError('Not a BMP file')
    length,offset=struct.unpack_from('<I',data,2)[0],struct.unpack_from('<I',data,10)[0]
    dib,w,h,planes,bits,compression=struct.unpack_from('<IiiHHI',data,14)
    if dib<40 or planes!=1 or bits!=24 or compression!=0:
        raise ValueError('Requires uncompressed 24-bit BMP, BITMAPINFOHEADER or newer')
    if not 640<=w<=1920 or not 360<=h<=1080:
        raise ValueError('Requires bottom-up BMP: width 640..1920, positive height 360..1080')
    stride=(w*3+3)&~3
    if not 54<=offset<length<=8388608 or offset+stride*h>length or length>len(data):
        raise ValueError('Invalid/truncated BMP header or pixel payload')
    return data[:length],w,h

def example():
    w,h=1920,1080
    colors=[(255,255,255),(255,255,0),(0,255,255),(0,255,0),
            (255,0,255),(255,0,0),(0,0,255),(0,0,0)]
    rows=[]
    for y in range(h-1,-1,-1):
        row=bytearray()
        for x in range(w):
            r,g,b=colors[min(x//240,7)]
            if y>=720:r=g=b=255 if ((x//64)^(y//64))&1 else 0
            if 956<=x<964 or 536<=y<544:r,g,b=255,0,0
            if x<8 or x>=w-8 or y<8 or y>=h-8:r=g=b=255
            row.extend((b,g,r))
        rows.append(row)
    payload=b''.join(rows)
    return (struct.pack('<2sIHHI',b'BM',54+len(payload),0,0,54)+
            struct.pack('<IiiHHIIiiII',40,w,h,1,24,0,len(payload),0,0,0,0)+payload)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bmp',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--example',action='store_true')
    args=parser.parse_args()
    if bool(args.bmp)==bool(args.example):parser.error('Choose exactly one of --bmp or --example')
    data=example() if args.example else args.bmp.read_bytes()
    data,w,h=validate(data)
    # Keep scanner input contiguous; one aligned BMP begins at sector zero.
    size=max(8*1024*1024,((len(data)+511)//512)*512)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('xb') as f:f.write(data);f.write(bytes(size-len(data)))
    if args.example:
        bmp_path=args.output.with_suffix('.bmp')
        with bmp_path.open('xb') as f:f.write(data)
        print(bmp_path)
    print(f'{args.output}: source={w}x{h}, output=1366x768, bytes={size}, BMP at sector 0')
