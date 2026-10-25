"""Exact before/after checks for the mutually exclusive award DSP clients."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,shutil,subprocess,time,sys
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--only',nargs='+',choices=['math','math_native','foil','foil_native','renderer','renderer_native','spotlight']);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 selected=a.only or ['math','math_native','foil','foil_native','renderer','renderer_native','spotlight']
 vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
 model=out/'vendor_mult18_functional.v';model.write_text(vendor.read_text().split('`pragma protect begin_protected',1)[0],encoding='utf-8')
 if any(n.startswith('renderer') for n in selected):
  from test_relief_bus import decode,decode_hq,savehex
  from test_board_rebalance import shade,packed_wall
  for filename,prefix in [('AWARD720.DLT','legacy'),('RELIEF720.DLT','relief')]:
   _,plate,tail,_=decode(ROOT/'award_media'/filename);savehex(out/(prefix+'_tail.hex'),tail)
   if prefix=='relief':
    savehex(out/'relief_base.hex',plate.view('<u2').ravel(),4);pal,_=decode_hq(tail)
    savehex(out/'lit_palettes.hex',[(shade(int(p),-16,6)<<8)|(int(p)&1) for p in pal[0]])
    savehex(out/'packed_wall.hex',[(packed_wall(d)<<8)|1 for d in range(128)])
 def run(name):
  native=name.endswith('_native');case=name.removesuffix('_native')
  paths=[ROOT/('tests/tb_shared_award_'+('fx' if case=='foil' else case)+'.v'),ROOT/'common/photo_award_math_bank.v']
  if case in ['foil','renderer']:paths += [ROOT/'common/award_fx.v',ROOT/'common/award_sprite_rom.v',ROOT/'tests/reference/shared_math/award_fx.v']
  if case=='spotlight':paths += [ROOT/'common/photo_spotlight_player.v',ROOT/'tests/reference/shared_math/photo_spotlight_player.v']
  if case=='renderer':paths += [ROOT/p for p in ['common/photo_award_render.v','common/photo_relief_player.v','common/photo_relief_motion.v','common/photo_relief_decode_cache.v','common/photo_relief_tables_compact_a.v','common/photo_spotlight_player.v','common/photo_display_pipe.v','tests/reference/shared_math/photo_award_render.v','tests/reference/shared_math/photo_relief_player.v','tests/reference/shared_math/photo_spotlight_player.v']]
  extra=['-DSHARED_DSP_NATIVE','-s','glbl'] if native else []
  if native:paths += [model,ROOT/'tests/relief_native_glbl.v']
  evidence=paths+[Path(__file__),ROOT/'tests/reference/shared_math/source.json']
  if case=='renderer':evidence += [ROOT/'tools/test_board_rebalance.py',ROOT/'tools/test_relief_bus.py',ROOT/'award_media/RELIEF720.DLT',ROOT/'award_media/AWARD720.DLT']
  hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};start=time.monotonic()
  binary=out/(name+'.vvp');flags=['-DWATER_SIM','-DRELIEF_SIM','-DERAM_SIM','-DSHARED_DSP_CHECK',*extra]
  r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012',*flags,'-s','tb','-o',str(binary),*map(str,paths)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=1200);log+=r.stdout+r.stderr
  lp=out/(name+'.log');lp.write_text(log,encoding='utf-8')
  passed=r.returncode==0 and 'PASS ' in log and not any(v in log for v in ['FATAL:','ERROR:']) and all(sha(p)==hashes[p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p)] for p in evidence)
  print(name+': '+log[-2000:],flush=True)
  return dict(test='shared_award_'+name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,external_inputs_sha256={str(vendor):sha(vendor)} if native else {},stimuli_sha256={p.name:sha(p) for p in out.glob('*.hex')} if case=='renderer' else {},log=str(lp),log_sha256=sha(lp),flags=flags)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:records=list(pool.map(run,selected))
 dest=out/'results.json';old=json.loads(dest.read_text()) if dest.exists() else [];names={r['test'] for r in records};dest.write_text(json.dumps([r for r in old if r['test'] not in names]+records,indent=2)+'\n')
 if not all(r['passed'] for r in records):sys.exit(1)
if __name__=='__main__':main()
