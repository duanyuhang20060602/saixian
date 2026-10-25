"""Verify the real SD cache's title byte routing; unrelated hardware uses shells."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--iverilog',type=Path,required=True);ap.add_argument('--records',type=Path,required=True);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 (out/'title_records.hex').write_bytes(a.records.read_bytes())
 text=(ROOT/'common/photo_sd_cache.v').read_text(encoding='utf-8');shells={}
 real=set(re.findall(r'\bmodule\s+(\w+)',text))|{'photo_sd_title_store'}
 for m in re.finditer(r'^\s*([a-z]\w*_\w+)\s*(?:#\((.*?)\))?\s+(\w+)\s*\((.*?)\);',text,re.M|re.S):
  module,parameters,instance,ports=m.groups()
  if module in real or module=='module':continue
  names=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',ports)));params=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',parameters or '')))
  if module in shells:
   names=list(dict.fromkeys(re.findall(r'input (\w+)',shells[module])+names));params=list(dict.fromkeys(re.findall(r'parameter (\w+)',shells[module])+params))
  if names:shells[module]='module '+module+(' #('+','.join('parameter '+p+'=0' for p in params)+')' if params else '')+'('+','.join('input '+p for p in names)+'); endmodule'
 shell=out/'hardware_shells.v';shell.write_text('\n'.join(shells.values()))
 files=[ROOT/n for n in ['tests/tb_sd_title_media.v','common/photo_sd_cache.v','common/photo_sd_title_store.v']]+[shell]
 inputs={str(p):sha(p) for p in files+[Path(__file__),out/'title_records.hex']};start=time.monotonic();binary=out/'media.vvp'
 r=subprocess.run([str(a.iverilog),'-g2012','-DTITLE_SIM','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:
  r=subprocess.run([str(a.iverilog.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=60);log+=r.stdout+r.stderr
 (out/'media.log').write_text(log)
 passed=r.returncode==0 and 'PASS ' in log and all(sha(Path(p))==v for p,v in inputs.items())
 (out/'results.json').write_text(json.dumps(dict(cases=[dict(test='media_wiring',passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=inputs,log_sha256=sha(out/'media.log'))]),indent=2)+'\n')
 print(log[-2500:]);assert passed
if __name__=='__main__':main()
