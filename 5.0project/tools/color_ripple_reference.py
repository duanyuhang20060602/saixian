"""Independent integer image model for the fixed-point colorful reveal."""
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]
NOISE=[(v if v<256 else v-512) for v in [int(s,16) for s in (ROOT/'common/fluid/water_color_noise.hex').read_text().split()]]
def phase(p):
    knots=[0,2,16,54,128,202,240,254,256]
    return 256 if p==256 else knots[p//32]+(knots[p//32+1]-knots[p//32])*(p%32)//32
def mapped(p,x,y):
    q=phase(p)
    ia=((x+y//2+q)//2)&255;ib=((y+x//2-q)//2)&255
    ic=(x+2*y+2*q)&255;id=(3*x-y+3*q)&255
    n=NOISE[ia]+NOISE[256+ib]+(NOISE[512+ic]+NOISE[768+id])//2
    dx,dy=abs(2*x-640),abs(y-360)
    r=max(dx,dy)+min(dx,dy)//4+min(dx,dy)//8
    delta=r+n-(4*q+q//2+q//8)
    alpha=max(0,min(256,128-2*delta))
    t=abs(delta)//8*8
    env=round(31*math.exp(-t*t/(2*110**2))*max(0,math.cos(t/734*5))) if t<512 else 0
    env=min(env,q*4 if q<8 else 256-q if q>224 else 31)
    if q in (0,256):alpha=q;env=0
    sx=max(0,min(638,x+(2*env if x<320 else -2*env)))//2*2
    return sx,y,sx,alpha,env,env//4

def lighting(w,env):
    gain=round(32/(1-.73*env/31));out=0
    for pos,bits in [(27,5),(21,6),(16,5),(11,5),(5,6),(0,5)]:
        v=(w>>pos)&((1<<bits)-1);out|=min((1<<bits)-1,(v*gain+16)//32)<<pos
    return out

def fringe(pixels,amounts):
    result=[]
    for i,v in enumerate(pixels):
        d=(amounts[i//2]//2)*(1 if i<320 else -1)
        r=pixels[2*max(0,min(319,i//2+d))+(i%2)]>>11
        b=pixels[2*max(0,min(319,i//2-d))+(i%2)]&31
        result.append((r<<11)|(v&0x7e0)|b)
    return result
