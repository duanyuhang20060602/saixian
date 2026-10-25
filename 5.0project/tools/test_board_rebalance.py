"""Independent exact-lighting oracle, cross-clock transport and 720p scanout."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time,struct,sys
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def exposure(c):
 # The existing 5.0 exposure table uses nearest-even rounding, including ties.
 q,r=divmod(510*c,255+c)
 return q+int(2*r>255+c or (2*r==255+c and q%2))
def shade(p,lx,ly):
 color=p>>16;n=p&65535
 nx=(n>>11)&31;ny=(n>>6)&31;nz=(n>>1)&31
 nx=(nx if nx<16 else nx-32)*2;ny=(ny if ny<16 else ny-32)*2
 dot=nx*lx+ny*ly+nz*16
 diffuse=max(0,min(255,dot//4));spec=max(0,min(255,dot+nz*16-1024))
 r=(color>>11)&31;g=(color>>5)&63;b=color&31
 rgb=[min(255,(((r<<3)|(r>>2))>>1)+(r*diffuse*33//2048)+(spec>>1)),
      min(255,(((g<<2)|(g>>4))>>1)+(g*diffuse*65//8192)+(spec>>2)),
      min(255,(((b<<3)|(b>>2))>>1)+(b*diffuse*33//2048)+(spec>>3))]
 return sum(exposure(c)<<s for c,s in zip(rgb,[16,8,0]))
def wall(d):return sum(exposure(c)<<s for c,s in zip([24+d,12+(d>>1),3+(d>>3)],[16,8,0]))
def packed_wall(d):
 p=wall(d);r=p>>16;g=(p>>8)&255;b=p&255;dg=g-(r>>1);db=b-(r>>3)
 assert 0<=dg<32 and 0<=db<16
 packed=(r<<9)|(dg<<4)|db
 assert (r<<16)|(((r>>1)+dg)<<8)|((r>>3)+db)==p
 return packed
def savehex(path,values,width=8):path.write_text(''.join(f'{int(v):0{width}x}\n' for v in values),encoding='utf-8')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--only',nargs='+',choices=['kernel','kernel_native','coprocessor','receiver','spi','player','player_native','cache']);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 from test_relief_bus import decode,decode_hq,vectors
 asset=ROOT/'award_media/RELIEF720.DLT';_,_,tail,_=decode(asset);pal,indices=decode_hq(tail)
 savehex(out/'raw_palettes.hex',pal.ravel())
 lights=[(-16,6),(15,6),(-24,-16),(24,16),(0,0),(7,-9)]
 cases=[];expected=[]
 for lx,ly in lights:
  for p in pal.ravel():
   p=int(p);cases.append(((lx&63)<<38)|((ly&63)<<32)|p);expected.append(shade(p,lx,ly))
 savehex(out/'kernel_inputs.hex',cases,11);savehex(out/'kernel_expected.hex',expected,6)
 expected_tables=[];queries=[]
 for angle in range(24):
  for lx,ly in [(-16,6),(24,-16)]:
   queries.append((1<<24)|(angle<<12)|((lx&63)<<6)|(ly&63))
   expected_tables.extend((shade(int(p),lx,ly)<<8)|(int(p)&1) for p in pal[angle])
   expected_tables.extend((packed_wall(d)<<8)|1 for d in range(128))
 savehex(out/'queries.hex',queries);savehex(out/'tables_expected.hex',expected_tables)
 savehex(out/'wall_table.hex',[wall(d) for d in range(128)],6)
 savehex(out/'lit_palettes.hex',[(shade(int(p),-16,6)<<8)|(int(p)&1) for p in pal[:2].ravel()])
 selected=a.only or ['kernel','kernel_native','coprocessor','receiver','spi','player','player_native','cache']
 if 'player' in selected or 'player_native' in selected:vectors(out,asset,relief=True)
 records=[]
 for name in selected:
  deps=['common/photo_relief_remote.v','common/photo_relief_remote_tables.v','common/photo_relief_tables_compact_a.v']
  if name=='spi':deps+=['common/photo_audio_link.v']
  if name in ['player','player_native']:deps=['common/photo_relief_player.v','common/photo_relief_motion.v','common/photo_relief_decode_cache.v']
  if name=='cache':deps=['common/photo_av_receiver.v']
  bench=name.removesuffix('_native')
  paths=[ROOT/f'tests/tb_board_rebalance_{bench}.v']+[ROOT/p for p in deps]
  extra=[];external=[]
  if name in ['kernel_native','player_native']:
   vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
   model=out/'vendor_mult18_functional.v';model.write_text(vendor.read_text().split('`pragma protect begin_protected',1)[0],encoding='utf-8')
   paths+=[model,ROOT/'tests/relief_native_glbl.v'];external=[vendor];extra=['-DRELIEF_NATIVE_DSP','-s','glbl']
  fixtures=list(out.glob('*.hex'));evidence=paths+[Path(__file__),ROOT/'tools/test_relief_bus.py',asset]
  hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};stimuli={p.name:sha(p) for p in fixtures}
  start=time.monotonic();binary=out/(name+'.vvp')
  r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DRELIEF_SIM','-DVICTORY_SIM',*extra,'-s','tb','-o',str(binary),*map(str,paths)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:
   r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=1200);log+=r.stdout+r.stderr
  lp=out/(name+'.log');lp.write_text(log,encoding='utf-8')
  passed=r.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and 'ERROR:' not in log and hashes=={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
  records.append(dict(test='rebalance_'+name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,external_inputs_sha256={str(p):sha(p) for p in external},stimuli_sha256=stimuli,log=str(lp),log_sha256=sha(lp),flags=['RELIEF_SIM','VICTORY_SIM',*extra]))
  print(name+': '+log[-2500:],flush=True)
  dest=out/'results.json';old=json.loads(dest.read_text()) if dest.exists() else [];old=[v for v in old if v['test']!=records[-1]['test']];dest.write_text(json.dumps(old+[records[-1]],indent=2)+'\n')
  if not passed:sys.exit(1)
if __name__=='__main__':main()
