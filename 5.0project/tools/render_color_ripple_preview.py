"""Render the verified fixed-point pipeline with existing photos (offline preview)."""
from pathlib import Path
import argparse,hashlib,json,math,subprocess,sys
import numpy as np
from PIL import Image,ImageDraw
from color_ripple_reference import NOISE,phase,mapped
ROOT=Path(__file__).resolve().parents[1]
X,Y=np.meshgrid(np.arange(320,dtype=np.int32)*2,np.arange(720,dtype=np.int32))
N=np.array(NOISE,dtype=np.int32).reshape(32,32)
ENV=np.array([round(31*math.exp(-(i*8)**2/(2*110**2))*max(0,math.cos(i*8/734*5))) for i in range(65)],dtype=np.int32)
GAIN=np.array([round(32/(1-.73*i/31)) for i in range(32)],dtype=np.int32)
def fields(p):
 q=phase(p)
 ia=((X+Y//2+q)//2)&255;ib=((Y+X//2-q)//2)&255
 ic=(X+2*Y+2*q)&255;id=(3*X-Y+3*q)&255
 flat=N.reshape(-1);n=flat[ia]+flat[256+ib]+(flat[512+ic]+flat[768+id])//2
 dx=np.abs(2*X-640);dy=np.abs(Y-360);lo=np.minimum(dx,dy);r=np.maximum(dx,dy)+lo//4+lo//8
 delta=r+n-(4*q+q//2+q//8);alpha=np.clip(128-2*delta,0,256)
 env=ENV[np.minimum(64,np.abs(delta)//8)];env=np.minimum(env,q*4 if q<8 else 256-q if q>224 else 31)
 if q in (0,256):alpha[:]=q;env[:]=0
 sx=np.clip(X+np.where(X<320,2*env,-2*env),0,638)//2*2
 return sx,alpha,env

def photo(path):
 im=Image.open(path).convert('RGB');assert im.size==(1280,720)
 a=np.array(im,dtype=np.int32)//np.array([8,4,8]);left=a[:,np.maximum(0,np.arange(0,1280,2)-1)]
 half=(left+2*a[:,::2]+a[:,1::2]+2)//4
 return a,half

def render(a,b,p):
 if p==0:return rgb(a[0])
 if p==256:return rgb(b[0])
 sx,alpha,env=fields(p);indices=np.repeat(sx,2,axis=1)+np.tile([0,1],320)
 yy=np.arange(720)[:,None];aa=a[1][yy,indices];bb=b[1][yy,indices]
 w=np.repeat(alpha,2,axis=1)[...,None];gain=np.repeat(GAIN[env],2,axis=1)[...,None]
 mixed=(aa*256+(bb-aa)*w+128)//256
 pixels=np.minimum(np.array([31,63,31]),(mixed*gain+16)//32)
 ca=env//8;direction=np.where(X<320,1,-1)
 ridx=np.clip(X//2+ca*direction,0,319);bidx=np.clip(X//2-ca*direction,0,319)
 ridx=np.repeat(ridx*2,2,axis=1)+np.tile([0,1],320);bidx=np.repeat(bidx*2,2,axis=1)+np.tile([0,1],320)
 out=pixels.copy();out[:,:,0]=pixels[yy,ridx,0];out[:,:,2]=pixels[yy,bidx,2]
 full=np.empty((720,1280,3),dtype=np.int32);full[:,::2]=out
 full[:,1::2]=(out+out[:,np.minimum(639,np.arange(640)+1)]+1)//2
 return rgb(full)
def rgb(a):return np.uint8((a<<np.array([3,2,3]))+(a>>np.array([2,4,2])))
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--photos',type=Path,required=True);ap.add_argument('--video',action='store_true');ap.add_argument('--ffmpeg',default='E:/Codex/Downloads/qiansai/.deps/media/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe');o=ap.parse_args();o.out.mkdir(parents=True,exist_ok=True)
 # Independent scalar versus vector renderer mapping at all edge phases.
 rng=np.random.default_rng(257)
 for p in [0,1,10,32,64,95,128,160,192,224,255,256]:
  sx,aa,ee=fields(p)
  for _ in range(128):
   xx=int(rng.integers(320));yy=int(rng.integers(720));ref=mapped(p,xx*2,yy)
   assert (int(sx[yy,xx]),int(aa[yy,xx]),int(ee[yy,xx]))==(ref[0],ref[3],ref[4])
 photos=[photo(o.photos/f'{i:02d}.bmp') for i in [1,2,3]]
 frames=[]
 for p in [64,96,112,128,144,160]:
  im=Image.fromarray(render(photos[0],photos[1],p));im.save(o.out/f'phase_{p:03d}.png');frames.append(im.resize((640,360)))
 sheet=Image.new('RGB',(1920,720));
 for i,im in enumerate(frames):sheet.paste(im,((i%3)*640,(i//3)*360))
 sheet.save(o.out/'color_ripple_rtl_model_contact.jpg',quality=95)
 if o.video:
  ff=o.ffmpeg
  video=o.out/'saixian_color_ripple_fixedpoint_720p60.mp4'
  enc=subprocess.Popen([ff,'-y','-loglevel','error','-f','rawvideo','-vcodec','rawvideo','-pix_fmt','rgb24','-s','1280x720','-r','60','-i','-','-an','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],stdin=subprocess.PIPE)
  try:
   for index in range(2):
    for _ in range(60):enc.stdin.write(rgb(photos[index][0]).tobytes())
    for step in range(85):enc.stdin.write(render(photos[index],photos[index+1],min(256,3*step+step//21)).tobytes())
   for _ in range(60):enc.stdin.write(rgb(photos[2][0]).tobytes())
   enc.stdin.close();assert enc.wait()==0
  except:enc.kill();raise
  print(video,flush=True)
 print('PASS fixed-point preview model checked against scalar oracle; offline preview, hardware pending',flush=True)
if __name__=='__main__':main()
