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
    size=576
    rng=np.random.default_rng(62027)
    palettes=[];frames=[];masks=[];errors=[];normal_errors=[]
    for frame in range(24):
        mask0=exr(art/f'mask_{frame+1:04d}.exr')
        n0=normals(exr(art/f'normal_{frame+1:04d}.exr'),mask0)
        color=np.asarray(Image.open(art/f'angle_{frame:02d}.png').convert('RGB').crop((352,48,928,624)).resize((size,size),Image.Resampling.LANCZOS))
        coverage=np.asarray(Image.fromarray(mask0[48:624,352:928]).resize((size,size),Image.Resampling.BOX))
        nd=np.stack([np.asarray(Image.fromarray((n0[...,i]*mask0)[48:624,352:928]).resize((size,size),Image.Resampling.BOX)) for i in range(3)],axis=-1)
        nd/=np.maximum(np.linalg.norm(nd,axis=-1,keepdims=True),1e-6)
        mask=coverage>.45
        feature=np.concatenate((color.astype(np.float32)/255,nd*.25),axis=-1)
        occupied=feature[mask];sample=occupied[rng.choice(len(occupied),min(6000,len(occupied)),replace=False)]
        centers=sample[rng.choice(len(sample),255,replace=False)].copy()
        for iteration in range(12):
            labels=nearest(sample,centers);counts=np.bincount(labels,minlength=255)
            for axis in range(6):
                sums=np.bincount(labels,weights=sample[:,axis],minlength=255);centers[counts>0,axis]=(sums[counts>0]/counts[counts>0]).astype(np.float32)
        indices=np.zeros(mask.shape,np.uint8);indices[mask]=(nearest(occupied,centers)+1).astype(np.uint8)
        rgb=np.clip(np.rint(centers[:,:3]*255),0,255).astype(np.uint8)
        nn=centers[:,3:];nn/=np.maximum(np.linalg.norm(nn,axis=1,keepdims=True),1e-6)
        pal=np.zeros(256,dtype='<u4');pal[1:]=(rgb565(rgb).astype(np.uint32)<<16)|pack_normal(nn)
        errors.append(float(np.mean((rgb[indices[mask]-1].astype(float)-color[mask])**2)))
        normal_errors.append(float(np.mean(np.arccos(np.clip((nn[indices[mask]-1]*nd[mask]).sum(axis=1),-1,1)))*180/np.pi))
        palettes.append(pal);frames.append(indices);masks.append(mask)
        print('PACK_HQ_ANGLE',frame,'color_PSNR',round(10*np.log10(255**2/errors[-1]),2),'normal_degrees',round(normal_errors[-1],2),flush=True)
    # Each row is PackBits: control <128 is a literal group (1..128),
    # otherwise it repeats the following material index (1..128 pixels).
    # The row's trailing transparent pixels are implicit.
    stream_offset=(64+24*256+24*size)*4
    tail=bytearray(stream_offset);directory=[]
    struct.pack_into('<8I',tail,0,0x38514852,size,size,24,256,64,64+24*256,stream_offset)
    for f,pal in enumerate(palettes):tail[(64+f*256)*4:(64+(f+1)*256)*4]=pal.tobytes()
    for frame in frames:
        for row in frame:
            a=list(map(int,row));limit=len(a)
            while limit and a[limit-1]==0:limit-=1
            a=a[:limit];encoded=bytearray();x=0
            while x<len(a):
                count=1
                while x+count<len(a) and a[x+count]==a[x] and count<128:count+=1
                if count>=3:encoded.extend((127+count,a[x]));x+=count;continue
                first=x;x+=count
                while x<len(a) and x-first<128:
                    count=1
                    while x+count<len(a) and a[x+count]==a[x] and count<128:count+=1
                    if count>=3:break
                    x+=min(count,128-(x-first))
                encoded.append(x-first-1);encoded.extend(a[first:x])
            assert 0<=len(encoded)<=768 and len(tail)<2097152
            if encoded and len(tail)%256+len(encoded)>256:tail.extend(bytes((-len(tail))%256))
            directory.append(len(tail)|(len(encoded)<<21));tail.extend(encoded)
    struct.pack_into('<'+str(len(directory))+'I',tail,(64+24*256)*4,*directory)
    used=len(tail);assert used<=2097152,('HQ tail overflow',used)
    np.savez_compressed(preview.parent/'native_materials.npz',palettes=np.stack(palettes),frames=np.stack(frames))
    tail.extend(bytes(2097152-used))
    # Preserve the exact approved background and its full-resolution normals.
    old=ROOT/'award_media/RELIEF720.DLT';old_blob=old.read_bytes();offset,length=struct.unpack_from('<2I',old_blob,512)
    head=bytearray(old_blob[:offset*4]);stream=old_blob[offset*4:(offset+length)*4]
    head[:8]=b'SXDLT008';struct.pack_into('<H',head,8,8)
    blob=head+stream;blob.extend(bytes((-len(blob))%512));tail_offset=len(blob)//4;blob.extend(tail)
    struct.pack_into('<I',blob,20,len(blob));struct.pack_into('<5I',blob,256,24,tail_offset,524288,0x524c4638,6)
    struct.pack_into('<I',blob,36,zlib.crc32(blob[512:]))
    out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(blob)
    preview.mkdir(parents=True,exist_ok=True)
    for f in [0,6,12,18]:
        words=palettes[f][frames[f]];c=words>>16
        rgb=np.stack((((c>>11)&31)*255//31,((c>>5)&63)*255//63,(c&31)*255//31),axis=-1).astype(np.uint8)
        image=Image.fromarray(rgb).resize((576,576),Image.Resampling.NEAREST)
        image.save(preview/f'cup_color_{f:02d}.png')
    manifest=dict(format='SXDLT008',bytes=len(blob),sha256=hashlib.sha256(blob).hexdigest(),frame_count=24,sprite_resolution=[size,size],display_origin=[352,48],display_resolution=[576,576],scale='1/1',palette='24 independent 256-entry RGB565 + surface-normal palettes',codec='Per-row PackBits with implicit trailing transparency; 21-bit byte offset and 11-bit byte length',tail_offset_words=tail_offset,tail_words=524288,used_tail_bytes=used,transport_words=985088,color_quantization_psnr_db=float(10*np.log10(255**2/np.mean(errors))),normal_mean_error_degrees=float(np.mean(normal_errors)),brightness_exposure=2,brightness_curve='round(510*c/(255+c)); highlight protection',hold_frames=10,hardware_validation='pending')
    out.with_suffix('.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8');print(json.dumps(manifest,indent=2),flush=True)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--art',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--preview',type=Path,required=True)
    a=ap.parse_args();prepare(a.art,a.output,a.preview)
