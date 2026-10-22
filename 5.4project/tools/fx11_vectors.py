from pathlib import Path
import random
from reference import warp,word,blend
def generate(TEST):
    rng=random.Random(76321)
    cases=[(0,0,0,0,998,346,454,432,0,0)]
    cases += [(1,p,0,0,0,0,0,0,0,0) for p in range(257)]
    cases += [(0,0,1,1,998,346,454,432,r,r+55) for r in [0,1,25,96,400,800,1050,1200]]
    cases += [(0,0,on0,on1,cx,1279-cx,cy,719-cy,r,r+17)
              for on0,on1 in [(1,0),(0,1),(1,1)]
              for cx,cy in [(0,0),(1279,719),(640,360),(91,628)] for r in [0,25,96,719,1400]]
    lines=[str(len(cases))]
    for cfg in cases:
        points=[(0,0),(639,719),(320,360),(639,0),(0,719)]+[(rng.randrange(640),rng.randrange(720)) for _ in range(251)]
        lines.append(' '.join(map(str,cfg))+' '+str(len(points)))
        for x,y in points:lines.append(f'{x} {y} '+' '.join(map(str,warp(x,y,cfg))))
    (TEST/'math_vectors.txt').write_text('\n'.join(lines),encoding='ascii')
    def average565(a,b):
        return (((((a>>11)+(b>>11)+1)//2)<<11) |
                (((((a>>5)&63)+((b>>5)&63)+1)//2)<<5) |
                (((a&31)+(b&31)+1)//2))
    def row_words(case,y):
        cfg=(1,128,0,0,0,0,0,0,0,0) if case==1 else (0,0,1,1,100,200,20,30,80,160) if case==2 else (0,0,0,0,0,0,0,0,0,0)
        base=0 if case==1 else 1382400
        half=[];masks=[]
        for x in range(320):
            sx,sy=warp(x*2,y,cfg)
            a=word(base+460800+sy*320+sx//2)
            p=blend(a,word(1152000+y*320+x),128) if case==1 else a
            half.extend([p>>16,p&65535]);masks.append(case==1 or sx!=x*2 or sy!=y)
        output=[]
        for x in range(320):
            if masks[x]:
                a,b=half[x*2:x*2+2];c=half[min(639,x*2+2)]
                output.extend([(a<<16)|average565(a,b),(b<<16)|average565(b,c)])
            else:output.extend([word(base+y*640+x*2),word(base+y*640+x*2+1)])
        return output
    values=[f'{v:08x}' for case in range(3) for y in range(8) for v in row_words(case,y)]
    (TEST/'reader_vectors.txt').write_text('\n'.join(values),encoding='ascii')
    def expand565(p):
        r=(p>>11)&31;g=(p>>5)&63;b=p&31
        return (r*8+(r>>2),g*4+(g>>4),b*8+(b>>2))
    checks=[]
    for mode in [6,0,7,5,9]:
        crc=0x811c9dc5
        for y in range(720):
            cfg=(1,128,0,0,0,0,0,0,0,0) if mode==6 else (0,0,1,1,998,346,454,432,600,400) if mode==0 else (0,0,0,0,0,0,0,0,0,0)
            half=[];masks=[]
            for x in range(320):
                sx,sy=warp(x*2,y,cfg)
                a=word(460800+sy*320+sx//2)
                p=blend(a,word(1152000+y*320+x),128) if mode==6 else a
                if mode in (5,9):
                    from effects_reference import mapped,lighting
                    aa,yy,bb,q,shade,shine=mapped(mode,128,False,x*2,y)
                    p=lighting(blend(word(460800+yy*320+aa//2),word(1152000+y*320+bb//2),q),shade,shine)
                half.extend([p>>16,p&65535]);masks.append(mode in (5,6,9) or sx!=x*2 or sy!=y)
            for x in range(320):
                if masks[x]:
                    a,b=half[x*2:x*2+2];c=half[min(639,x*2+2)]
                    pixels=[a,average565(a,b),b,average565(b,c)]
                else:
                    a=word(y*640+x*2);b=word(y*640+x*2+1);pixels=[a>>16,a&65535,b>>16,b&65535]
                for p in pixels:
                    c=expand565(p);rgb=(c[0]<<16)|(c[1]<<8)|c[2]
                    crc=((crc^rgb)*0x01000193)&0xffffffff
        checks.append(crc)
    (TEST/'frame_checksums.hex').write_text(''.join(f'{v:08x}\n' for v in checks),encoding='ascii')
    from effects_reference import mapped,lighting
    erng=random.Random(170103)
    elines=[]
    for fx in range(11):
        for p in range(257):
            for right in [0,1]:
                points=[(x,y) for x in [0,2,318,320,638] for y in [0,89,90,359,360,629,630,719]]
                points += [(erng.randrange(320)*2,erng.randrange(720)) for _ in range(8)]
                for x,y in points:
                    rgb=erng.getrandbits(32);values=mapped(fx,p,right,x,y)
                    elines.append(' '.join(map(str,[fx,p,right,1,x,y,x,y,*values]))+f' {rgb:08x} {lighting(rgb,values[-2],values[-1]):08x}')
    for n in range(1024):
        x=erng.randrange(320)*2;y=erng.randrange(720);wx=max(0,min(639,x+erng.randrange(-8,9)));wy=max(0,min(719,y+erng.randrange(-14,15)))
        fx=erng.randrange(11);p=erng.randrange(257);rgb=erng.getrandbits(32);values=mapped(fx,p,0,x,y,wx,wy,False)
        elines.append(' '.join(map(str,[fx,p,0,0,x,y,wx,wy,*values]))+f' {rgb:08x} {lighting(rgb,values[-2],values[-1]):08x}')
    (TEST/'effects_vectors.txt').write_text('\n'.join(elines),encoding='ascii')
    fx_lines=[]
    for fx in range(11):
        for right in [0,1]:
            for progress in [0,64,128,192,256]:
                for y in range(8):
                    half=[]
                    for x in range(320):
                        sx,sy=warp(x*2,y,(1,progress,0,0,0,0,0,0,0,0)) if fx==6 else (x*2,y)
                        a,yy,b,q,shade,shine=mapped(fx,progress,right,x*2,y,sx,sy)
                        v=lighting(blend(word(460800+yy*320+a//2),word(1152000+y*320+b//2),q),shade,shine)
                        half.extend([v>>16,v&65535])
                    for x in range(320):
                        if progress==256:out=[word(691200+y*640+2*x),word(691200+y*640+2*x+1)]
                        else:
                            a,b=half[2*x:2*x+2];c=half[min(639,2*x+2)]
                            out=[(a<<16)|average565(a,b),(b<<16)|average565(b,c)]
                        fx_lines.extend(f'{v:08x}' for v in out)
    (TEST/'fx_reader_vectors.txt').write_text('\n'.join(fx_lines),encoding='ascii')

