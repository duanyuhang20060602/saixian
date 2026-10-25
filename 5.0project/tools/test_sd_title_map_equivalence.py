"""Prove the registered common endpoint predicate preserves effect outputs."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--iverilog',type=Path,required=True);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 assets=list((ROOT/'common/fluid').glob('*.hex'))
 for p in assets:shutil.copy2(p,out/p.name)
 files=[ROOT/n for n in ['tests/tb_sd_title_map_equivalence.v','common/fluid/water_priority_map.v','common/fluid/water_effect_map_base.v','tests/reference/sd_title/water_priority_map.v']]
 inputs={str(p):sha(p) for p in files+assets+[Path(__file__)]};start=time.monotonic();binary=out/'map.vvp'
 r=subprocess.run([str(a.iverilog),'-g2012','-DWATER_SIM','-DFX11_ROM_ROOT="./"','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:
  r=subprocess.run([str(a.iverilog.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=900);log+=r.stdout+r.stderr
 (out/'map_equivalence.log').write_text(log)
 passed=r.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and all(sha(Path(p))==v for p,v in inputs.items())
 (out/'results.json').write_text(json.dumps(dict(cases=[dict(test='map_equivalence',passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=inputs,log_sha256=sha(out/'map_equivalence.log'))]),indent=2)+'\n')
 print(log[-2500:]);assert passed
if __name__=='__main__':main()
