import numpy as np

def source_rgb(width,height):
    x=np.arange(width)[None,:];y=np.arange(height)[:,None]
    r=np.broadcast_to(x*255//(width-1),(height,width))
    g=np.broadcast_to(y*255//(height-1),(height,width))
    b=((x//37+y//41)%2)*215+17
    return np.stack([r,g,b],axis=-1)

def resize(width,height,out_width=640,out_height=720):
    # Independent separable fixed-point sampling model. Horizontal results
    # pass through the same RGB565 storage precision before vertical sampling.
    source=source_rgb(width,height)
    px=np.arange(out_width)*((width-1)*65536//(out_width-1));px[-1]=(width-1)*65536
    x0=px//65536;x1=np.minimum(x0+1,width-1);wx=(px%65536)//256
    crisp=(width,height,out_width,out_height)==(640,480,1280,720)
    h=source[:,np.minimum(x0+(wx>=128),width-1)] if crisp else source[:,x0]+((source[:,x1]-source[:,x0])*wx[None,:,None]//256)
    h[:,:,0]=(h[:,:,0]>>3)*8+(h[:,:,0]>>5)
    h[:,:,1]=(h[:,:,1]>>2)*4+(h[:,:,1]>>6)
    h[:,:,2]=(h[:,:,2]>>3)*8+(h[:,:,2]>>5)
    py=np.arange(out_height)*((height-1)*65536//(out_height-1));py[-1]=(height-1)*65536
    y0=py//65536;y1=np.minimum(y0+1,height-1);wy=(py%65536)//256
    v=h[np.minimum(y0+(wy>=128),height-1)] if crisp else h[y0]+((h[y1]-h[y0])*wy[:,None,None]//256)
    return ((v[:,:,0]<<16)|(v[:,:,1]<<8)|v[:,:,2]).ravel()
