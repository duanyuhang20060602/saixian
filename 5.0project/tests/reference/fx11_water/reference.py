import math

def vector(x,y,cx,cy,radius,enabled=False,water=False,progress=0):
    dx,dy=2*x-cx,y-cy
    rx=(dx*9)>>4 if water else dx
    r=math.isqrt(rx*rx+dy*dy)
    if water:
        phase=((r*869)>>8)-((progress*2445)>>8)
        s=round(math.sin((phase&511)*2*math.pi/512)*4096) if enabled and r*256<=progress*720 else 0
        p=s-(s>>2)
        gain=(p*(round(65536/r) if r else 0))>>12
        gain=((gain+32768)&65535)-32768
    else:
        d=r-radius
        p=round(-d/25*math.exp(-.5*(d/25)**2)*14*256) if enabled and -96<=d<=96 else 0
        inv=round(65536/r) if r else 0
        gain=(p*inv)>>12
        gain=((gain+32768)&65535)-32768
    return (dx*gain)>>12,(dy*gain)>>12

def warp(x,y,cfg):
    mode,progress,on0,on1,cx0,cx1,cy0,cy1,r0,r1=cfg
    if mode:return x,y
    dx0,dy0=vector(x,y,640 if mode else cx0,360 if mode else cy0,r0,mode or on0,mode,progress)
    dx1,dy1=vector(x,y,cx1,cy1,r1,on1 and not mode)
    return max(0,min(639,(2*x+dx0+dx1)//2)),max(0,min(719,y+max(-6,min(6,dy0+dy1))))

def word(address):
    return ((address&65535)<<16)|((address^65535)&65535)

def blend(a,b,alpha):
    fields=[(27,31),(21,63),(16,31),(11,31),(5,63),(0,31)]
    out=0
    for shift,mask in fields:
        old=(a>>shift)&mask;new=(b>>shift)&mask
        out|=((old*256+(new-old)*alpha+128)>>8)<<shift
    return out
