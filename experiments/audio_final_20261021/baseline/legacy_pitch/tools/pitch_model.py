from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
RATIOS=[65536,82570,49097,98193,131072]

def fir_stereo(source):
    q=np.load(ROOT/'results/fir_q15.npy')
    return np.column_stack([np.clip((np.convolve(source[:,c].astype(np.int64),q)[:len(source)]+16384)>>15,-32768,32767) for c in range(2)])

def model(source,modes,trace=False):
    source=np.asarray(source,dtype=np.int64)
    filtered=fir_stereo(source)
    centers=np.vstack([np.zeros((31,2),dtype=np.int64),source])[:len(source)]
    ring=np.zeros((4096,4),dtype=np.int64)
    out=np.zeros((len(source),6),dtype=np.int64)
    active=0;gain=0;startup=0;phase=0
    def blend(a,b,w):return np.clip(a+((b-a)*int(w)+32768)//65536,-32768,32767)
    for n in range(len(source)):
        wanted=int(modes[n]);desired=0 if active==0 else 32768 if active>=3 else 65536
        if wanted!=active:
            if gain>512:gain-=512
            elif gain:gain=0
            else:active=wanted;phase=0
        elif gain<desired:gain=min(gain+512,desired)
        elif gain>desired:gain=max(gain-512,desired)
        startup=min(startup+4,256) if n>=2114 else 0
        w=n&4095;ring[w,:2]=centers[n];ring[w,2:]=filtered[n]
        p2=phase^(1<<26)
        frac=phase&65535
        ia=(w-64-(phase>>16))&4095;ib=(w-64-(p2>>16))&4095
        a=blend(ring[ia,2:],ring[(ia-1)&4095,2:],frac)
        b=blend(ring[ib,2:],ring[(ib-1)&4095,2:],frac)
        hw=65536-((phase>>10)&65535) if phase&(1<<26) else ((phase>>10)&65535)
        wet=blend(b,a,hw);dry=ring[(w-1088)&4095,:2]
        mixed=blend(dry,wet,gain)
        result=blend(np.zeros(2,dtype=np.int64),mixed,startup*256) if n+1>=2114 else np.zeros(2,dtype=np.int64)
        phase=0 if active==0 else (phase+65536-RATIOS[active])&((1<<27)-1)
        desired=0 if active==0 else 32768 if active>=3 else 65536
        ready=(n+1>=2114 and startup==256 and active==wanted and gain==desired)
        out[n]=[int(result[0]),int(result[1]),active,gain,phase,int(ready)]
    return out if trace else out[:,:2]
