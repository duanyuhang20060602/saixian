"""Generate FONTS.BIN for ordinary file copy; never opens or writes a disk."""
from pathlib import Path
import argparse,struct
from PIL import Image,ImageDraw,ImageFont
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--font',type=Path,default=Path('C:/Windows/Fonts/msyh.ttc'));ap.add_argument('--legacy-image',action='store_true',help='Optional old-format image for historical regression only');a=ap.parse_args()
 a.out.mkdir(parents=True,exist_ok=True);font=ImageFont.truetype(str(a.font),15)
 records=bytearray(b'SXFONT01'+bytes(504))
 chars=[chr(i) for i in range(128)]
 for hi in range(0xa1,0xff):
  for lo in range(0xa1,0xff):
   try:chars.append(bytes([hi,lo]).decode('gb2312'))
   except UnicodeDecodeError:chars.append('?')
 for ch in chars:
  im=Image.new('1',(16,16));d=ImageDraw.Draw(im)
  if ord(ch)>=32:
   l,t,r,b=d.textbbox((0,0),ch,font=font);d.text(((16-r+l)//2-l,(16-b+t)//2-t),ch,font=font,fill=1)
  for y in range(16):records.extend(struct.pack('>H',sum(int(im.getpixel((x,y))!=0)<<(15-x) for x in range(16))))
 records.extend(bytes(-len(records)%512));(a.out/'FONTS.BIN').write_bytes(records)
 if not a.legacy_image:
  print('Created FONTS.BIN for copying to the root of a FAT16/FAT32 card;',len(chars),'glyphs');return
 # 64MiB FAT16 volume. MBR LBA2048, FAT16 root LBA2177, first data LBA2209.
 size=131072;start=2048;total=size-start;clusters=(total-161)//8
 boot=bytearray(512);boot[:3]=b'\xeb\x3c\x90';boot[3:11]=b'SAIXIAN ';struct.pack_into('<HBHBHHBHHHII',boot,11,512,8,1,2,512,0,0xf8,64,32,64,start,total)
 boot[36:39]=b'\x80\x00\x29';boot[39:43]=b'SX01';boot[43:54]=b'SAIXIANFONT';boot[54:62]=b'FAT16   ';boot[510:]=b'\x55\xaa'
 fat=bytearray(64*512);struct.pack_into('<HH',fat,0,0xfff8,0xffff);n=(len(records)+4095)//4096
 for i in range(n):struct.pack_into('<H',fat,(2+i)*2,0xffff if i==n-1 else 3+i)
 root=bytearray(32*512);root[:11]=b'FONTS   BIN';root[11]=0x20;struct.pack_into('<H',root,26,2);struct.pack_into('<I',root,28,len(records))
 mbr=bytearray(512);mbr[450]=0x06;struct.pack_into('<II',mbr,454,start,total);mbr[510:]=b'\x55\xaa'
 with (a.out/'TEXT_DEMO_CARD.img').open('wb') as f:
  f.truncate(size*512);f.seek(0);f.write(mbr);f.seek(start*512);f.write(boot);f.write(fat);f.write(fat);f.write(root);assert f.tell()==2209*512;f.write(records)
 for i,s in enumerate(['欢迎来到赛显','冠军 CHAMPION','中国加油 2026','中文英文数字123']):(a.out/f'line{i}.bin').write_bytes(f'@{i}:'.encode()+s.encode('gb2312')+b'\r\n')
 print('Created FAT16 image and font library at LBA2209;',len(chars),'glyphs')
if __name__=='__main__':main()
