"""Reuse eight source angles of the existing RELIEF720.DLT, not new artwork."""
from pathlib import Path
import struct,zlib,hashlib,json
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[1];TD=ROOT/'project/src/td_project';HDL=ROOT/'project/src/user_source/hdl_source'
SOURCE=ROOT.parent/'5.0project/award_media/RELIEF720.DLT'
blob=SOURCE.read_bytes();assert blob[:8]==b'SXDLT008'
assert zlib.crc32(blob[512:])==struct.unpack_from('<I',blob,36)[0]
_,off,_,_,_=struct.unpack_from('<5I',blob,256);raw=blob[off*4:]
assert struct.unpack_from('<8I',raw)==(0x38514852,576,576,24,256,64,6208,80128)
pal=np.frombuffer(raw,dtype='<u4',count=6144,offset=256).reshape(24,256)
desc=np.frombuffer(raw,dtype='<u4',count=13824,offset=6208*4).reshape(24,576)
images=[];rgba=[]
for f in range(0,24,3):
 idx=np.zeros((576,576),np.uint8)
 for y,word in enumerate(desc[f]):
  word=int(word);p=word&0x1fffff;end=p+(word>>21);x=0
  while p<end:
   command=raw[p];p+=1;n=(command&127)+1
   if command<128:idx[y,x:x+n]=np.frombuffer(raw,dtype=np.uint8,count=n,offset=p);p+=n
   else:idx[y,x:x+n]=raw[p];p+=1
   x+=n
  assert p==end and x<=576
 words=pal[f][idx];color=words>>16;surface=words&65535
 c=np.stack((((color>>11)&31)*255/31,((color>>5)&63)*255/63,(color&31)*255/31),axis=-1)
 nx=((surface>>11)&31).astype(int);ny=((surface>>6)&31).astype(int);nz=((surface>>1)&31).astype(int)
 nx=np.where(nx>=16,nx-32,nx)*2;ny=np.where(ny>=16,ny-32,ny)*2
 dot=nx*-16+ny*6+nz*16;diffuse=np.clip(dot/4,0,255)/255
 # Fixed offline light, then the existing scene-only exposure curve. Rotation
 # remains FPGA frame selection; this preview does not claim live touch light.
 c=np.clip(c*(.55+.45*diffuse[...,None]),0,255)
 c=np.rint(510*c/(255+c)).astype(np.uint8)
 alpha=(idx!=0).astype(np.uint8)*255
 im=Image.fromarray(np.dstack((c,alpha)),'RGBA').resize((96,96),Image.Resampling.LANCZOS)
 rgba.append(im);images.append(np.asarray(im))
all_rgb=np.concatenate([im[:,:,:3][im[:,:,3]>=128] for im in images])
swatch=Image.fromarray(all_rgb.reshape(-1,1,3),'RGB').quantize(colors=15,method=Image.Quantize.MEDIANCUT)
colors=swatch.getpalette()[:45];palette=[(0,0,0)]+[tuple(colors[i:i+3]) for i in range(0,45,3)]
frames=[]
for f,im in enumerate(images):
 rgb=im[:,:,:3].astype(np.int32);p=np.array(palette[1:],np.int32)
 index=(((rgb[:,:,None,:]-p)**2).sum(axis=-1).argmin(axis=-1)+1).astype(np.uint8)
 index[im[:,:,3]<128]=0;frames.append(index)
 out=np.array(palette,np.uint8)[index];out[index==0]=(9,21,37)
 Image.fromarray(out).resize((384,384),Image.Resampling.NEAREST).save(ROOT/f'results/trophy_angle_{f}.png')
flat=np.stack(frames).ravel().astype(np.uint16)
(ROOT/'results/trophy_expected.hex').write_text('\n'.join(f'{int(v):x}' for v in flat)+'\n')
words=flat[0::4]|(flat[1::4]<<4)|(flat[2::4]<<8)|(flat[3::4]<<12)
assert len(words)==18432
for bank in range(9):
 vals=words[bank*2048:(bank+1)*2048]
 text='\n'.join(f'{w:04x}' for w in vals)+'\n'
 (TD/f'trophy_{bank}.hex').write_text(text);(HDL/f'trophy_{bank}.hex').write_text(text)
 mif='WIDTH=16;\nDEPTH=2048;\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\nCONTENT BEGIN\n'
 mif+=''.join(f'{i:03X} : {int(v):04X};\n' for i,v in enumerate(vals))+'END;\n'
 (TD/f'trophy_{bank}.mif').write_text(mif);(HDL/f'trophy_{bank}.mif').write_text(mif)
s='function [23:0] trophy_color;input [3:0] i;begin case(i)\n'
s+=''.join(f"{i}:trophy_color=24'h{r:02x}{g:02x}{b:02x};\n" for i,(r,g,b) in enumerate(palette))
s+='default:trophy_color=0;endcase end endfunction\n'
(HDL/'trophy_palette.vh').write_text(s)
(ROOT/'results/trophy_source.json').write_text(json.dumps({'source':str(SOURCE),'source_sha256':hashlib.sha256(blob).hexdigest(),
 'source_angles':list(range(0,24,3)),'preview_size':[96,96],'display_size':[384,384],
 'palette':palette,'light':'fixed offline light; no live relighting','bank_words':2048,'bank_count':9},indent=2))
print('Prepared original trophy: 8 angles, 96x96, 16 indexed colors, 9 RAM32K target')
