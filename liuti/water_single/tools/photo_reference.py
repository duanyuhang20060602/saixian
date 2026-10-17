from pathlib import Path
import os
WORK=Path(os.environ.get('WATER_TEST_WORK',r'E:\Codex\Work\saixian_water_validation'))

def prepare(root):
    import numpy as np
    from PIL import Image
    from effects_reference import mapped,lighting
    from reference import warp,blend
    WORK.mkdir(parents=True,exist_ok=True)
    images=[];halves=[]
    for k in range(1,6):
        a=np.array(Image.open(root/'tf_assets'/f'{k:02}.bmp').convert('RGB'),dtype=np.uint32)
        assert a.shape==(720,1280,3),'Real-photo fixtures require the delivered native BMP set'
        native=((a[:,:,0]>>3)<<11)|((a[:,:,1]>>2)<<5)|(a[:,:,2]>>3)
        even=native[:,::2];odd=native[:,1::2];left=np.column_stack((even[:,0],odd[:,:-1]))
        half=np.zeros_like(even)
        for shift,mask in [(11,31),(5,63),(0,31)]:
            half|=(( ((left>>shift)&mask)+2*((even>>shift)&mask)+((odd>>shift)&mask)+2 )//4)<<shift
        images.append(native);halves.append(half)
    np.savetxt(WORK/'photo_data.hex',np.concatenate([np.r_[a[:32].ravel(),b[:32].ravel()] for a,b in zip(images,halves)]),fmt='%04x')
    def average(a,b):
        return sum(((((a>>s)&m)+((b>>s)&m)+1)//2)<<s for s,m in [(11,31),(5,63),(0,31)])
    with (WORK/'photo_golden.hex').open('w',encoding='ascii') as f:
        for photo in range(5):
            new=(photo+1)%5
            for fx in range(11):
                for p in [128,256]:
                    for y in range(8):
                        if p==256:
                            row=images[new][y]
                            words=[(int(row[x])<<16)|int(row[x+1]) for x in range(0,1280,2)]
                        else:
                            pixels=[]
                            for x in range(320):
                                sx,sy=warp(x*2,y,(1,p,0,0,0,0,0,0,0,0)) if fx==6 else (x*2,y)
                                a,yy,b,q,shade,shine=mapped(fx,p,photo%2,x*2,y,sx,sy)
                                aa=(int(halves[photo][yy,a&~1])<<16)|int(halves[photo][yy,(a&~1)+1])
                                bb=(int(halves[new][y,b&~1])<<16)|int(halves[new][y,(b&~1)+1])
                                value=lighting(blend(aa,bb,q),shade,shine);pixels.extend([value>>16,value&65535])
                            words=[]
                            for x in range(320):
                                a,b=pixels[2*x:2*x+2];c=pixels[min(639,2*x+2)]
                                words.extend([(a<<16)|average(a,b),(b<<16)|average(b,c)])
                        f.write(''.join(f'{word:08x}\n' for word in words))
    return WORK/'photo_data.hex',WORK/'photo_golden.hex'
