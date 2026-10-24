"""Pack original 24-angle gold art into an SXDLT006 surface package.

The external artwork directory contains angle_00..23.png, mask/normal EXRs,
background_720p.png and background wall AOVs. No bitstream is changed here.
"""
from pathlib import Path
import argparse, hashlib, json, struct, zlib
import numpy as np
import OpenEXR
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]

def exr(path):
    channels=OpenEXR.File(str(path)).channels()
    return (channels['RGB'] if 'RGB' in channels else next(iter(channels.values()))).pixels.copy()

def normals(raw,mask):
    n=raw/np.maximum(mask[...,None],1e-6)*2-1
    n/=np.maximum(np.linalg.norm(n,axis=-1,keepdims=True),1e-6)
    return n

def pack_normal(n):
    x=np.clip(np.rint(n[...,0]*15),-15,15).astype(np.int32)
    y=np.clip(np.rint(n[...,1]*15),-15,15).astype(np.int32)
    z=np.clip(np.rint(n[...,2]*31),0,31).astype(np.int32)
    return (((x&31)<<11)|((y&31)<<6)|(z<<1)|1).astype(np.uint16)

def rgb565(rgb):
    a=np.asarray(rgb,dtype=np.uint16)
    return ((a[...,0]>>3)<<11)|((a[...,1]>>2)<<5)|(a[...,2]>>3)

def nearest(data,centers):
    answer=[]
    for start in range(0,len(data),4096):
        block=data[start:start+4096]
        distance=((block[:,None,:]-centers[None,:,:])**2).sum(axis=2)
        answer.append(distance.argmin(axis=1))
    return np.concatenate(answer)

def prepare(art,out,preview):
    colors=[];directions=[];masks=[]
    for frame in range(24):
        mask=exr(art/f'mask_{frame+1:04d}.exr')
        n=normals(exr(art/f'normal_{frame+1:04d}.exr'),mask)
        yy,xx=np.where(mask>.5)
        assert xx.min()>=352 and xx.max()<928 and yy.min()>=48 and yy.max()<624,(frame,xx.min(),xx.max(),yy.min(),yy.max())
        color=np.array(Image.open(art/f'angle_{frame:02d}.png').convert('RGB').crop((352,48,928,624)).resize((192,192),Image.Resampling.LANCZOS))
        m=np.asarray(Image.fromarray(mask[48:624,352:928]).resize((192,192),Image.Resampling.BOX))
        # Coverage-weighted normals prevent silhouettes from inheriting the
        # empty AOV's arbitrary direction during downsampling.
        nd=np.stack([np.asarray(Image.fromarray((n[...,i]*mask)[48:624,352:928]).resize((192,192),Image.Resampling.BOX)) for i in range(3)],axis=-1)
        nd/=np.maximum(np.linalg.norm(nd,axis=-1,keepdims=True),1e-6)
        colors.append(color);directions.append(nd);masks.append(m>.45)
    color=np.stack(colors);normal=np.stack(directions);mask=np.stack(masks)
    # Joint color/direction quantization: identical gold colors on differently
    # facing surfaces must remain distinct under interactive lighting.
    features=np.concatenate((color.astype(np.float32)/255,normal*.45),axis=-1)
    occupied=features[mask]
    rng=np.random.default_rng(62026)
    sample=occupied[rng.choice(len(occupied),min(18000,len(occupied)),replace=False)]
    centers=sample[rng.choice(len(sample),255,replace=False)].copy()
    for iteration in range(16):
        labels=nearest(sample,centers)
        counts=np.bincount(labels,minlength=255)
        for axis in range(6):
            sums=np.bincount(labels,weights=sample[:,axis],minlength=255)
            centers[counts>0,axis]=(sums[counts>0]/counts[counts>0]).astype(np.float32)
        print('PALETTE_ITERATION',iteration+1,flush=True)
    indices=np.zeros(mask.shape,np.uint8)
    indices[mask]=(nearest(occupied,centers)+1).astype(np.uint8)
    rgb=np.clip(np.rint(centers[:,:3]*255),0,255).astype(np.uint8)
    n=centers[:,3:];n/=np.maximum(np.linalg.norm(n,axis=1,keepdims=True),1e-6)
    palette=np.zeros(256,dtype='<u4')
    palette[1:]=(rgb565(rgb).astype(np.uint32)<<16)|pack_normal(n)
    tail=palette.tobytes()+indices.tobytes()
    assert len(tail)==885760 and len(tail)<=921600
    tail+=bytes(921600-len(tail))
    background_image=Image.open(art/'background_720p.png').convert('RGB')
    overlay=Image.new('RGBA',background_image.size)
    draw=ImageDraw.Draw(overlay)
    draw.text((67,43),'赛显',font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',18),fill=(242,220,169,255))
    draw.text((640,660),'冠 军',font=ImageFont.truetype('C:/Windows/Fonts/msyhbd.ttc',46),fill=(238,194,94,255),anchor='mm')
    draw.text((640,701),'C H A M P I O N',font=ImageFont.truetype('C:/Windows/Fonts/bahnschrift.ttf',14),fill=(220,194,135,255),anchor='mm')
    background=np.asarray(Image.alpha_composite(background_image.convert('RGBA'),overlay).convert('RGB'))
    wall_mask=exr(art/'wall_mask_0001.exr')
    wall_normal=normals(exr(art/'wall_normal_0001.exr'),wall_mask)
    # Ordered quantization prevents the quiet floor gradient from banding.
    threshold=(np.array([[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]])+.5)/16
    threshold=np.tile(threshold,(180,320))
    red=np.clip(np.floor(background[...,0]/8+threshold),0,31).astype(np.uint16)
    green=np.clip(np.floor(background[...,1]/4+threshold),0,63).astype(np.uint16)
    blue=np.clip(np.floor(background[...,2]/16+threshold),0,15).astype(np.uint16)*2
    base=(red<<11)|(green<<5)|blue
    wall=(wall_mask>.5)&(np.asarray(overlay)[...,3]==0)
    base[wall]=pack_normal(wall_normal[wall])
    # Low halfword is the first displayed pixel. The existing DLT reader and
    # color packer intentionally swap halves when transporting the base frame.
    words=np.frombuffer(base.astype('<u2').tobytes(),dtype='<u4')
    stream=struct.pack('<I',0x40000000|len(words))+words.tobytes()
    header=bytearray(1536)
    header[:8]=b'SXDLT006'
    struct.pack_into('<HHHH',header,8,6,512,1280,720)
    struct.pack_into('<I',header,16,1)
    struct.pack_into('<4I',header,24,460800,1,32,0)
    struct.pack_into('<I',header,40,2)
    struct.pack_into('<8I',header,512,384,len(stream)//4,300000000,zlib.crc32(words.tobytes()),zlib.crc32(stream),0,0,0)
    blob=header+stream
    blob.extend(bytes((-len(blob))%512))
    tail_offset=len(blob)//4
    blob.extend(tail)
    struct.pack_into('<I',blob,20,len(blob))
    struct.pack_into('<5I',blob,256,24,tail_offset,230400,0x524c4636,6)
    struct.pack_into('<I',blob,36,zlib.crc32(blob[512:]))
    out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(blob)
    preview.mkdir(parents=True,exist_ok=True)
    decoded=rgb[np.maximum(indices.astype(np.int16)-1,0)]
    mse=float(np.mean((decoded[mask].astype(float)-color[mask])**2))
    frames=[]
    for frame in range(24):
        canvas=Image.fromarray(background.copy())
        sprite=Image.fromarray(decoded[frame]).resize((576,576),Image.Resampling.NEAREST)
        alpha=Image.fromarray((mask[frame]*255).astype(np.uint8)).resize((576,576),Image.Resampling.NEAREST)
        canvas.paste(sprite,(352,48),alpha)
        frames.append(canvas)
    frames[0].save(preview/'indexed_color_reference.png')
    frames[0].save(preview/'indexed_rotation_reference.webp',save_all=True,append_images=frames[1:],duration=250,loop=0,quality=85)
    manifest={'format':'SXDLT006','bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest(),
        'frame_count':24,'sprite_resolution':[192,192],'display_scale':3,'display_origin':[352,48],
        'palette':'256 x (RGB565 color + signed XY/positive Z surface direction)',
        'background':'full-resolution per-pixel surface normals; untagged floor pixels are RGB565',
        'tail_offset_words':tail_offset,'tail_words':230400,'used_tail_bytes':885760,
        'transport_words':691200,'color_quantization_psnr_db':10*np.log10(255**2/max(mse,1e-12)),
        'preview_scope':'Indexed color/rotation only. The interactive FPGA shader is not simulated in this preview.',
        'hardware_validation':'pending'}
    out.with_suffix('.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print(json.dumps(manifest,indent=2))

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--art',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True);ap.add_argument('--preview',type=Path,required=True)
    a=ap.parse_args();prepare(a.art,a.output,a.preview)
