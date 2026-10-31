"""Check complete screen protocol, default restoration and actual ranking pixels."""
from pathlib import Path
import argparse,subprocess,hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1];IV=Path('C:/iverilog/bin/iverilog.exe')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();a.out.mkdir(parents=True,exist_ok=True);out=a.out.resolve();records=[]
 for name,bench,sources,flags in [('parser','tb_complete_hmi_parser.v',['match/photo_serial_text_runtime.v'],['-DRANK_SIM']),('rank_pixels','tb_complete_hmi_rank_pixels.v',['saixian_battle_result_fx_pipelined.v'],['-DRANK_SIM'])]:
  d=out/name;d.mkdir(exist_ok=True)
  for f in ['photo_rank_header.hex','photo_rank_glyphs.hex','photo_rank_columns.hex']:shutil.copy2(ROOT/'common'/f,d/f)
  files=[ROOT/'tests'/bench,*[ROOT/'common'/s for s in sources]]
  hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),*files]}
  cmd=[str(IV),'-g2012',*flags,'-s','tb','-o',str(d/'run.vvp'),*map(str,files)]
  r=subprocess.run(cmd,capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:r=subprocess.run([str(IV.with_name('vvp.exe')),str(d/'run.vvp')],cwd=d,capture_output=True,text=True,timeout=120);log+=r.stdout+r.stderr
  (d/'run.log').write_text(log);passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
  records.append({'test':'complete_hmi_'+name,'passed':passed,'inputs_sha256':hashes,'log':str(d/'run.log'),'log_sha256':hashlib.sha256((d/'run.log').read_bytes()).hexdigest()});print(name+': '+log[-2000:],flush=True)
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n');assert all(r['passed'] for r in records)
if __name__=='__main__':main()
