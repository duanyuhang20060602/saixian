"""Full remote-relief scanout with refresh and concurrent framebuffer writes."""
from pathlib import Path
import argparse,hashlib,json,subprocess,shutil,time,sys,concurrent.futures
ROOT=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',required=True,type=Path);ap.add_argument('--vectors',required=True,type=Path);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 for name in ['relief_tail.hex','lit_palettes.hex','wall_table.hex']:shutil.copy2(a.vectors/name,out/name)
 for asset in (ROOT/'common/fluid').glob('*.hex'):shutil.copy2(asset,out/asset.name)
 from test_relief_bus import GEOMETRY,FRAMEBUFFER
 names=['tests/tb_rebalance_bus.v','common/photo_relief_player.v','common/photo_relief_motion.v','common/photo_relief_decode_cache.v','common/photo_award_memory.v',*GEOMETRY,*FRAMEBUFFER]
 vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
 model=out/'vendor_mult18_functional.v';model.write_text(vendor.read_text().split('`pragma protect begin_protected',1)[0],encoding='utf-8')
 def run(native):
  name='bus_native' if native else 'bus';files=[ROOT/p for p in names]+([model,ROOT/'tests/relief_native_glbl.v'] if native else [])
  evidence=files+[Path(__file__),ROOT/'tools/test_relief_bus.py',ROOT/'award_media/RELIEF720.DLT']
  h={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};start=time.monotonic();binary=out/(name+'.vvp');flags=['-DWATER_SIM','-DRELIEF_SIM','-DVICTORY_SIM','-DFX11_ROM_ROOT=""']+(['-DRELIEF_NATIVE_DSP','-s','glbl'] if native else [])
  r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012',*flags,'-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=1200);log+=r.stdout+r.stderr
  lp=out/(name+'.log');lp.write_text(log,encoding='utf-8');passed=r.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and 'ERROR:' not in log
  print(name+': '+log[-1200:],flush=True)
  return dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=h,external_inputs_sha256={str(vendor):sha(vendor)} if native else {},stimuli_sha256={p.name:sha(p) for p in out.glob('*.hex')},log=str(lp),log_sha256=sha(lp),flags=flags)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:records=list(pool.map(run,[False,True]))
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n')
 if not all(r['passed'] for r in records):sys.exit(1)
if __name__=='__main__':main()
