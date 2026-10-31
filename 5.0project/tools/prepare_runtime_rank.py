"""Keep the old sprint heading and share one RAM for editable runner glyphs."""
from pathlib import Path
import argparse,struct
ROOT=Path(__file__).resolve().parents[1]
CHARS='0123456789.道秒选手 '
def expected():
 atlas=[int(v,16) for v in (ROOT/'src/board_a/user_source/hdl_source/saixian_sprint_atlas.hex').read_text().split()]
 assert len(atlas)==8192
 header=[]
 for v in atlas[224*32:256*32]:header.extend([v&65535,v>>16])
 lib=(ROOT/'examples/TF卡素材/GLYPHS.BIN').read_bytes();font=[0]*2048
 for i,ch in enumerate(CHARS):
  b=ch.encode('gb2312');code=b[0] if len(b)==1 else 128+(b[0]-161)*94+b[1]-161
  g=code//8;offset=code%8;assert lib[g*512:g*512+8]==b'SXGLYP01'
  rows=struct.unpack('>16H',lib[g*512+16+offset*32:g*512+48+offset*32])
  font[1024+i*16:1040+i*16]=rows
 columns=[]
 for x in range(512):
  valid=0;kind=0;field=15;offset=0
  if x<48:valid=1;kind=0 if x<24 else 1;field=0;offset=x%24
  elif 56<=x<104:valid=1;kind=2 if x<80 else 0;field=11;offset=(x-56)%24
  elif 112<=x<304:valid=1;kind=3;field=(x-112)//24;offset=(x-112)%24
  elif x>=368:
   valid=1;part=(x-368)//24;offset=(x-368)%24
   if part in (0,1,3,4):kind=4;field={0:0,1:1,3:2,4:3}[part]
   else:kind=0;field=10 if part==2 else 12
  columns.append((valid<<15)|(kind<<12)|(field<<8)|((offset*2//3)<<4))
 return {'photo_rank_header':header,'photo_rank_glyphs':font,'photo_rank_columns':columns}
def verify():
 for name,words in expected().items():
  assert [int(v,16) for v in (ROOT/'common'/f'{name}.hex').read_text().split()]==words,name
  assert (ROOT/'common'/f'{name}.mif').read_text()==mif(words),name
 return True
def mif(words):return f'WIDTH=16;\nDEPTH={len(words)};\nADDRESS_RADIX=UNS;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'+''.join(f'{i} : {v:04X};\n' for i,v in enumerate(words))+'END;\n'
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--write',action='store_true');a=p.parse_args()
 if a.write:
  for name,words in expected().items():
   (ROOT/'common'/f'{name}.hex').write_text(''.join(f'{v:04x}\n' for v in words))
   (ROOT/'common'/f'{name}.mif').write_text(mif(words))
 verify();print('PASS original sprint heading and shared editable-rank font assets')
