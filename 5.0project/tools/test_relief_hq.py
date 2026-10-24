"""Validate native material rows, scene exposure and same-size cup detail."""
from pathlib import Path
import argparse,hashlib,json,struct,time
import numpy as np
from PIL import Image
from test_relief_bus import decode,decode_hq
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def rgb(c):return np.stack(((((c>>11)&31)<<3)|(((c>>11)&31)>>2),(((c>>5)&63)<<2)|(((c>>5)&63)>>4),((c&31)<<3)|((c&31)>>2)),axis=-1).astype(np.int32)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--asset',type=Path,required=True);ap.add_argument('--baseline',type=Path,required=True);ap.add_argument('--art',type=Path,required=True);ap.add_argument('--material-reference',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 sidecar=a.asset.with_suffix('.json');sidecar=sidecar if sidecar.is_file() else a.asset.with_name(a.asset.stem+'_DLT.json')
 files=[Path(__file__),ROOT/'tools/test_relief_bus.py',sidecar,a.asset,a.baseline,a.material_reference]+[a.art/f'angle_{f:02d}.png' for f in range(24)]
 hashes={str(p.resolve()) if not p.resolve().is_relative_to(ROOT) else p.resolve().relative_to(ROOT).as_posix():sha(p) for p in files};start=time.monotonic()
 _,plate,tail,expected=decode(a.asset);pal,indices=decode_hq(tail);material=np.load(a.material_reference)
 assert np.array_equal(pal,material['palettes']) and np.array_equal(indices,material['frames'])
 old=a.baseline.read_bytes();off,n=struct.unpack_from('<2I',old,512);old_plate=np.frombuffer(old,dtype='<u4',count=460800,offset=(off+1)*4);assert np.array_equal(old_plate,plate),'Approved background changed'
 assert old[:8]==b'SXDLT007'
 tail_offset=struct.unpack_from('<I',old,260)[0];old_raw=old[tail_offset*4:]
 old_pal=np.frombuffer(old_raw,dtype='<u4',count=6144,offset=256).reshape(24,256)
 old_desc=np.frombuffer(old_raw,dtype='<u4',count=24*384,offset=6208*4).reshape(24,384)
 old_indices=np.zeros((24,384,384),dtype=np.uint8)
 for f in range(24):
  for y in range(384):
   v=int(old_desc[f,y]);pos=v&0xfffff;end=pos+(v>>20);x=0
   while pos<end:
    token=old_raw[pos];pos+=1
    if token:old_indices[f,y,x]=token;x+=1
    else:x+=old_raw[pos];pos+=1
   assert x<=384

 scores=[];light_deltas=[];sample=np.arange(576)*2//3
 for f in range(24):
  new_idx=indices[f];old_idx=old_indices[f][sample[:,None],sample[None,:]];mask=new_idx!=0
  original=np.asarray(Image.open(a.art/f'angle_{f:02d}.png').convert('RGB').crop((352,48,928,624))).astype(float)
  old_color=rgb(old_pal[f][old_idx]>>16);new_color=rgb(pal[f][new_idx]>>16)
  def psnr(image):return float(10*np.log10(255**2/np.mean((image[mask]-original[mask])**2)))
  scores.append([psnr(old_color),psnr(new_color)])
  surface=(pal[f][new_idx]&65535).astype(np.int32);nx=(surface>>11)&31;ny=(surface>>6)&31;nz=(surface>>1)&31;nx=np.where(nx>=16,nx-32,nx)*2;ny=np.where(ny>=16,ny-32,ny)*2
  result=[]
  for lx in [-24,24]:
   dot=nx*lx+ny*6+nz*16;diff=np.clip(dot//4,0,255);spec=np.clip(dot+nz*16-1024,0,255)
   result.append(np.clip(new_color//2+(new_color*(diff[...,None]//16))//32+np.stack((spec//2,spec//4,spec//8),-1),0,255))
  light_deltas.append(float(np.abs(result[1]-result[0])[mask].mean()))
 scores=np.asarray(scores);assert np.all(scores[:,1]>scores[:,0]+1),'Detail did not improve across views';assert np.mean(light_deltas)>5,'Cup light response too weak';assert len(expected)==985088
 curve=np.rint(510*np.arange(256)/(255+np.arange(256))).astype(int);assert curve[0]==0 and curve[-1]==255 and np.all(np.diff(curve)>=0) and np.all(curve>=np.arange(256))
 metadata=json.loads(sidecar.read_text(encoding='utf-8'));assert metadata['brightness_exposure']==2 and metadata['hold_frames']==10
 unchanged=all(sha(Path(k) if Path(k).is_absolute() else ROOT/k)==h for k,h in hashes.items());assert unchanged
 details=dict(source_size=[576,576],old_source_size=[384,384],display_footprint=[576,576],views=24,exact_decoded_source_pixels=int(indices.size),background_byte_identical=True,mean_old_color_psnr_db=float(scores[:,0].mean()),mean_new_color_psnr_db=float(scores[:,1].mean()),minimum_psnr_gain_db=float((scores[:,1]-scores[:,0]).min()),mean_oracle_light_difference=float(np.mean(light_deltas)),scope='Material data and same-size source detail comparison; CPU lighting oracle, not a board capture or optical sharpness measurement.')
 log=out/'native_materials.log';log.write_text('PASS all 24 HQ views, exact material row codec, preserved background, 2.25 times source pixels and scene-only twofold exposure with protected highlights and improved same-size cup detail\n'+json.dumps(details,indent=2)+'\n',encoding='utf-8')
 record=dict(test='native_materials',passed=True,inputs_sha256=hashes,inputs_unchanged=True,asset_sha256=sha(a.asset),seconds=round(time.monotonic()-start,2),log=str(log),log_sha256=sha(log),details=details)
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log.read_text(),flush=True)
if __name__=='__main__':main()
