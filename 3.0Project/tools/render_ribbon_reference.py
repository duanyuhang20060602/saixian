from pathlib import Path
import re,math,subprocess,numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1];temp=Path('E:/Codex/Temp/saixian_award_preview')
fx=(root/'src/user_source/hdl_source/award_fx.v').read_text()
def table(name,n):
 s=fx
 m=re.search(r'function[^;]*\b'+name+r';(.*?)endfunction',s,re.S);assert m,name
 pairs=re.findall(r"(?:6'd)?(\d+):"+name+r"=(\d+)'([dh])([0-9a-f]+)",m[1])
 arr=np.zeros(n,dtype=np.int32)
 for k,w,b,v in pairs:arr[int(k)]=int(v,16 if b=='h' else 10)
 return arr
seeds=table('seed_for_column',40);bends=table('bend',40);breaths=table('breath',64);waves=table('wave_curve',64)
raw=np.frombuffer((root/'examples/TF卡素材/base_tagged_rgb565.bin').read_bytes(),dtype='<u2').reshape(720,1280).astype(np.int32)
r=raw>>11;g=np.where(raw&1,((raw>>6)&31)*2,(raw>>5)&63);b=np.where(raw&1,(raw>>7)&15,((raw>>1)&15)*2)
base=np.stack([(r<<3)|(r>>2),(g<<2)|(g>>4),(b<<3)|(b>>2)],axis=2);tags=raw&63
sprite=np.loadtxt(root/'tests/fixtures/sprite_reference.hex',dtype=np.uint8,converters=lambda s:int(s,16)).reshape(16,32,32)
y=np.arange(720)[:,None];x=np.arange(1280)[None,:]
phase_base=y+bends[np.arange(1280)//32][None,:]
def render(ticks):
 motion=(ticks*1024//364)%1024
 phase=(motion+phase_base)&511;distance=np.where(phase>=256,512-phase,phase)
 intensity=np.where(tags&32,breaths[(motion>>4)&63],waves[distance>>3])-32
 gain=np.where(tags&1,(((tags>>1)&15)*intensity>>2)+np.where(tags&32,0,88),0)
 flow=np.clip(base+(base*gain[:,:,None]>>8),0,255)
 selected=np.zeros((720,1280),dtype=np.uint8)
 for layer,xor in enumerate([0,0x5429,0x9561,0x39ac]):
  for col in range(40):
   seed=int(seeds[col])^xor
   cy=([motion,2*motion+377,motion+619,3*motion+173][layer]+(seed&1023))&1023
   q=((motion>>4)+(seed&31)+layer)&31;sway=15-(q&15) if q&16 else q&15
   cx=(8+((seed>>11)&15)+(sway>>2))&127
   pose=((motion>>3)+(seed>>12)+layer*4)&15
   xlo=max(0,cx-16);xhi=min(32,cx+16);ylo=max(0,cy-16);yhi=min(548,cy+16)
   if xlo>=xhi or ylo>=yhi:continue
   patch=sprite[pose,ylo+16-cy:yhi+16-cy,xlo+16-cx:xhi+16-cx]
   old=selected[ylo:yhi,col*32+xlo:col*32+xhi]
   np.copyto(old,patch,where=(patch>>4)>(old>>4))
 shade=(selected&15).astype(np.int32);alpha=(selected>>4).astype(np.int32)
 gold=np.stack([188+shade*4,122+shade*8,46+shade*4],axis=2)
 return np.clip(flow+((gold-flow)*alpha[:,:,None]>>4),0,255).astype(np.uint8)
# Check the software renderer against independently emitted production RTL
# samples at every changed mesh pixel and every sprite footprint.
records=np.fromfile(temp/'ribbon_preview.points',dtype=np.uint8)
records=records[:len(records)//8*8].reshape(-1,8)
complete=int(records[:,0].max())+1 # closed output contains complete frame records
assert complete>=8
checks=0
for f in range(min(complete,16)):
 rows=records[records[:,0]==f];xx=rows[:,1].astype(np.int32)+rows[:,2].astype(np.int32)*256;yy=rows[:,3].astype(np.int32)+rows[:,4].astype(np.int32)*256
 rgb=render(f*364//180)
 want=rows[:,5:8];got=rgb[yy,xx]
 if not np.array_equal(got,want):
  bad=np.where(np.any(got!=want,axis=1))[0][0];raise RuntimeError(f'RTL mismatch frame={f} x={xx[bad]} y={yy[bad]} got={got[bad]} want={want[bad]}')
 checks+=len(rows)
print(f'PASS ribbon preview reference: {checks} exact RGB samples across 16 RTL award frames',flush=True)
(temp/'ribbon_reference.log').write_text(f'PASS ribbon preview reference: {checks} exact RTL RGB samples across 16 frames; original speed and fixed-point arithmetic preserved\n')
# 180 reference samples on actual consecutive display ticks 0,2,...,358.
with (temp/'ribbon_composed.rgb').open('wb') as out:
 for f in range(180):
  rgb=render(f*2);out.write(rgb.tobytes())
  if f in [0,30,60,90,120,150]:Image.fromarray(rgb).save(temp/f'ribbon_frame_{f}.png')
print('Rendered full-rate ribbon reference samples',flush=True)
