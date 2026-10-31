"""Independent integer model of the eleven live transition coordinate maps."""
import math

def mapped(fx,p,right,x,y,wx=None,wy=None,enabled=True):
    if fx==6 and enabled:
        from color_ripple_reference import mapped as color_map
        return color_map(p,x,y)
    wx=x if wx is None else wx;wy=y if wy is None else wy
    px=2*x;u=1279-px if right else px
    a=b=px;mix=p;shade=shine=0
    if enabled:
        if fx==0:
            front=6*p-128;d=u-front;mix=max(0,min(256,128-8*d))
            if 0<=d<128:
                i=d//4;a=front+round(96*2/math.pi*math.acos(i*4/128))
                shade=round(24*(1-i/31)**1.5);shine=int(i in (0,1,2,3))
            else:a=u
            if right:a=1279-a
        elif fx==1:
            scale=abs(256-2*p);half=5*scale//2
            if abs(px-640)<=half and scale>=16:
                a=b=640+((px-640)*round(262144/max(16,scale))>>10)
                mix=0 if p<112 else 256 if p>=144 else (p-112)*8
                shade=(256-scale)//16;shine=3 if half-abs(px-640)<8 else 0
            else:shade=28;mix=p
        elif fx==2:
            band=[0,4,1,5,2,6,3,7][min(7,y//90)]
            t=max(0,min(256,p+p//4-8*band));ease=2*t-(t*t//256)
            bend=round(24*math.sin(math.pi*(y%90)/90))*min(t,256-t)//128
            travel=5*ease+bend;d=u-(1280-travel);mix=max(0,min(256,128+8*d))
            a=u+travel;b=a-1280
            if right:a=1279-a;b=1279-b
            if 0<t<256:shade=2;shine=2 if -12<d<12 else 0
        elif fx==3:
            col=min(7,u//160);origin=col*160;lx=u-origin-80
            t=max(0,min(256,p+p//2-col*16));scale=abs(256-2*t);half=scale*5//16
            if abs(lx)<=half and scale>=16:
                a=b=origin+80+(lx*round(262144/max(8,scale))>>10)
                mix=0 if t<112 else 256 if t>=144 else (t-112)*8
                shade=(256-scale)>>4;shine=3 if 0<t<256 and half-abs(lx)<5 else 0
            else:a=b=u;mix=256;shade=12
            if right:a=1279-a;b=1279-b
        elif fx==4:
            front=5*(256-p);a=u*round(262144/max(8,256-p))>>10;b=u;d=u-front
            mix=max(0,min(256,128+8*d))
            if d<0:
                metric=a%160;shade=min(24,p>>4 if metric<80 else p>>3)
                shine=2 if p>8 and (metric<4 or metric>=156) else 0
            if right:a=1279-a;b=1279-b
        elif fx==5:
            wave=round(32*math.sin(2*math.pi*((y+(y//64)*8)&63)/64))
            front=6*p-128+(wave*min(p,256-p)>>7);d=u-front
            mix=max(0,min(256,128-8*d));a=b=u
            if abs(d)<32:a+=d>>1
            shade=6 if 0<d<32 else 0;shine=6 if abs(d)<6 else 2 if abs(d)<16 else 0
            if right:a=1279-a;b=1279-b
        elif fx==7:
            delta=9*p*p-(px-640)**2-(y-360)**2
            mix=max(0,min(256,128+(delta>>7)))
            if abs(delta)<24576:a+=delta>>11
            shade=4 if -24576<delta<0 else 0;shine=7 if abs(delta)<8192 else 2 if abs(delta)<16384 else 0
        elif fx==8:
            row=min(3,y//180);tilted=u+((y-row*180-90)>>1)
            col=0 if tilted<320 else 1 if tilted<640 else 2 if tilted<960 else 3
            order=(col*3)^(row*5);t=max(0,min(256,2*p-order*16))
            travel=(t*t>>8)*2;d=tilted-col*320+travel-320;a=u+travel;b=u
            mix=max(0,min(256,128+8*d));shade=t>>5 if mix<256 else 0;shine=4 if abs(d)<5 else 0
            if right:a=1279-a;b=1279-b
        elif fx==9:
            a=640+((px-640)*round(262144/max(8,256-p))>>10)
            b=640+((px-640)*round(262144/max(8,p))>>10)
            d=p*3-abs(px-640);mix=max(0,min(256,128+8*d))
            env=min(p,256-p);shade=24 if abs(px-640)>(256-p)*5//2 and d<0 else env>>4
            metric=abs(px-640)+abs(y-360)
            if env>16 and (metric&63)<3:shine=2;shade=4
        elif fx==10:
            wave=round(32*math.sin(2*math.pi*((y+(y//64)*8)&63)/64))
            half=(p*p>>8)*3;center=640+(wave*min(p,256-p)>>8)
            if right:center=1280-center
            d=half-abs(px-center);mix=max(0,min(256,128+8*d));a=px+(half if px<center else -half)
            if abs(d)<24:a+=d>>2
            shade=8 if -32<d<0 else 0;shine=5 if abs(d)<5 else 1 if abs(d)<12 else 0
        else:a=2*wx
    if not enabled or p in (0,256):
        a=2*wx;b=px;mix=p if enabled else 0;shade=shine=0
    return (max(0,min(639,a//2)),y if enabled and fx!=6 else wy,
            max(0,min(639,b//2)),mix,shade,shine)

def lighting(word,shade,shine):
    out=0
    for pos,bits in [(27,5),(21,6),(16,5),(11,5),(5,6),(0,5)]:
        c=(word>>pos)&((1<<bits)-1)
        value=max(0,min((1<<bits)-1,c-c*shade//32+(shine<<(3 if bits==6 else 2))))
        out|=value<<pos
    return out
