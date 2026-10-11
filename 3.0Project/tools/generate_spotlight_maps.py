from pathlib import Path
import math,numpy as np
root=Path(__file__).resolve().parents[1]
# Gaussian cross sections and a soft emitter boundary replace clipped triangle
# edges. Four subcell samples reduce aliasing before the 8x pixel interpolation.
def ease(t):
    t=np.clip(t,0,1);return t*t*(3-2*t)
def mix(a,b,t):return a+(b-a)*t
maps=[]
gx,gy=np.meshgrid(np.arange(160)*8+4,np.arange(90)*8+4)
for f in range(120):
    t=f/10
    gather=0 if t<2.5 else ease((t-2.5)/2) if t<4.5 else 1 if t<8.8 else 1-ease((t-8.8)/3.2)
    tx,ty,point=640,185,0
    if 5.8<=t<7.3:
        u=ease((t-5.8)/1.5);tx,ty,point=mix(640,754,u),mix(185,120,u),u
    elif 7.3<=t<8.8:
        u=ease((t-7.3)/1.5);tx,ty,point=mix(754,640,u),mix(120,335,u),1
    elif t>=8.8:tx,ty,point=640,335,1-ease((t-8.8)/2)
    beams=[]
    directions=[-260,10,285,995,1270,1540]
    for k,ox in enumerate((350,430,505,775,850,930)):
        oy=526+(5 if k%3==1 else 0);ax=mix(directions[k]+110*math.sin(2*math.pi*t/12+k*.7),tx,gather);ay=mix(-200,ty,gather)
        beams.append((ox,oy,ax,ay,mix(55,24,gather),.23+.05*gather))
    for k,(ox,oy) in enumerate(((24,18),(146,33),(1134,33),(1256,18))):
        ax=mix(760+150*math.sin(t*math.pi/6+k) if k<2 else 520-150*math.sin(t*math.pi/6+k),tx,gather)
        beams.append((ox,oy,ax,mix(640,ty,gather),mix(40,20,gather),.12+.04*gather))
    field=0
    for dx,dy in ((-2,-2),(2,-2),(-2,2),(2,2)):
        x,y=gx+dx,gy+dy;trans=np.ones_like(x,dtype=float)
        for ox,oy,ax,ay,width,power in beams:
            vx,vy=ax-ox,ay-oy;dist=math.hypot(vx,vy);ux,uy=vx/dist,vy/dist
            along=(x-ox)*ux+(y-oy)*uy;cross=(x-ox)*uy-(y-oy)*ux
            radius=np.maximum(2,width*np.maximum(0,along)/dist*.6)
            a=power*np.exp(-.5*(cross/radius)**2)*ease(along/24)
            trans*=1-a
        focal=gather*(.14+.18*point)*np.exp(-((x-tx)**2+(y-ty)**2)/(mix(75,38,point)**2*.3))
        field+=(1-trans+focal)/4
    m=np.minimum(220,np.rint(field*255)).astype(np.uint8);m[gy>=548]=0;maps.append(m)
(root/'examples/TF卡素材/spotlight_maps.bin').write_bytes(np.array(maps).tobytes())
print('Native AA foil ROM, 120 smooth light frames, unbiased phase and light quantization prepared')
