"""Regress late scan status after silent audio preload has stopped PCM reads."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe'
 bench=ROOT/'tests/tb_boot_catalog_poll.v';source=ROOT/'common/photo_audio_link.v'
 records=[]
 for typed,aw in [(0,10),(1,11)]:
  text=bench.read_text(encoding='utf-8').replace('.TYPED_PAGE(1)',f'.TYPED_PAGE({typed})')
  tb=out/f'poll_typed_{typed}.v';tb.write_text(text,encoding='ascii');binary=tb.with_suffix('.vvp')
  files=[tb,source,ROOT/'common/photo_boot_screen.v'];hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
  r=subprocess.run([str(iv),'-g2012','-P',f'tb.FIFO_AW={aw}','-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=600);log+=r.stdout+r.stderr
  tb.with_suffix('.log').write_text(log,encoding='utf-8');print(log[-2200:],flush=True)
  assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
  records.append({'test':f'delayed_catalog_typed_{typed}','passed':r.returncode==0 and 'PASS ' in log and 'FATAL' not in log,'inputs_sha256':hashes})
 (out/'results.json').write_text(json.dumps(records,indent=2),encoding='utf-8');assert all(r['passed'] for r in records)
if __name__=='__main__':main()
