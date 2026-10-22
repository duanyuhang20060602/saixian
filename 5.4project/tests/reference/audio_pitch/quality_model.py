from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
RATIOS=[65536,82570,49097,98193,131072]

def model(source,modes,trace=False,diagnostics=None):
    source=np.asarray(source,dtype=np.int64);modes=np.asarray(modes)
    qs=np.load(ROOT/'results/fir_q15.npy')
    filters=np.array([np.column_stack([np.convolve(source[:,c],q)[:len(source)] for c in range(2)]) for q in qs])
    filters=np.clip((filters+16384)>>15,-32768,32767)
    centers=np.vstack([np.zeros((31,2),dtype=np.int64),source])[:len(source)]
    ring=np.zeros((4096,4),dtype=np.int64);out=np.zeros((len(source),6),dtype=np.int64)
    active=gain=startup=phase=0;offset=[0,0];prev=[False,False];corr=None
    updates=[]
    def blend(a,b,w):return np.clip(a+((b-a)*int(w)+32768)//65536,-32768,32767)
    def cubic(base,frac):
        ym,y0,y1,y2=[ring[(base-i)&4095,2:] for i in [-1,0,1,2]]
        c3=(-ym+3*y0-3*y1+y2)>>1;c2=(2*ym-5*y0+4*y1-y2)>>1;c1=(-ym+y1)>>1
        v=((c3*frac+32768)>>16)+c2
        v=((v*frac+32768)>>16)+c1
        return np.clip(((v*frac+32768)>>16)+y0,-32768,32767)
    for n in range(len(source)):
        wanted=int(modes[n]);desired=0 if active==0 else 32768 if active>=3 else 65536
        p2=phase^(1<<26);pi=phase>>16;mute=[pi>=1280,256<=pi<1024]
        bases=[n-128-(phase>>16),n-128-(p2>>16)]
        if corr is None and n>=2700 and active!=0 and active==wanted and any(m and not p for m,p in zip(mute,prev)):
            head=int(mute[1] and not prev[1]);other=1-head
            corr=[head,bases[head],bases[other]-offset[other]-(2048 if active==2 else 0),0,2**24-1,0]
        prev=mute
        if wanted!=active:
            if gain>512:gain-=512
            elif gain:gain=0
            else:active=wanted;phase=0;offset=[0,0];corr=None
        elif gain<desired:gain=min(gain+512,desired)
        elif gain>desired:gain=max(gain-512,desired)
        startup=min(startup+4,256) if n>=2304 else 0
        w=n&4095;ring[w,:2]=centers[n];ring[w,2:]=filters[active,n]
        p2=phase^(1<<26);pi=phase>>16;frac=phase&65535
        a=cubic(n-128-(phase>>16)-offset[0],frac)
        b=cubic(n-128-(p2>>16)-offset[1],frac)
        x=(phase>>8)&65535;m=65536-x if x>=32768 else x
        smooth=65536-((m*m)>>15) if x>=32768 else (m*m)>>15
        hw=smooth if pi<256 else 65536 if pi<1024 else 65536-smooth if pi<1280 else 0
        wet=blend(b,a,hw);dry=ring[(w-1152)&4095,:2];mixed=blend(dry,wet,gain)
        result=blend(np.zeros(2,dtype=np.int64),mixed,startup*256) if n+1>=2304 else np.zeros(2,dtype=np.int64)
        phase=0 if active==0 else (phase+65536-RATIOS[active])&((1<<27)-1)
        desired=0 if active==0 else 32768 if active>=3 else 65536
        ready=n+1>=2304 and startup==256 and active==wanted and gain==desired
        out[n]=[int(result[0]),int(result[1]),active,gain,phase,int(ready)]
        if corr is not None and active==wanted:
            head,target,ref,candidate,best_score,best_offset=corr
            k=candidate-64;ts=np.arange(16)*4
            score=int(np.abs(ring[(target-k-ts)&4095,2:]-ring[(ref-ts)&4095,2:]).sum())
            if score<best_score:best_score=score;best_offset=k
            if candidate==128:
                new_pi=phase>>16;muted=[new_pi>=1280,256<=new_pi<1024]
                if muted[head]:offset[head]=best_offset;updates.append((n,head,best_offset,best_score))
                corr=None
            else:corr=[head,target,ref,candidate+1,best_score,best_offset]
        else:corr=None
    if diagnostics is not None:diagnostics['alignment_updates']=updates
    return out if trace else out[:,:2]
