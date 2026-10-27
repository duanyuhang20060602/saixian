"""Compare the actual SD cache watchdogs with the frozen original module."""
from pathlib import Path
import argparse,hashlib,json,re,os,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);temp=out/'temp';temp.mkdir(exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 text=(ROOT/'common/photo_sd_cache.v').read_text();real=set(re.findall(r'\bmodule\s+(\w+)',text));shells={}
 for m in re.finditer(r'^\s*([a-z]\w*_\w+)\s*(?:#\((.*?)\))?\s+(\w+)\s*\((.*?)\);',text,re.M|re.S):
  module,parameters,instance,ports=m.groups()
  if module in real or module=='module':continue
  names=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',ports)));params=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',parameters or '')))
  if names:shells[module]='module '+module+(' #('+','.join('parameter '+p+'=0' for p in params)+')' if params else '')+'('+','.join('input '+p for p in names)+'); endmodule'
 shell=out/'hardware_shells.v';shell.write_text('\n'.join(shells.values()));files=[ROOT/'tests/tb_media_deadlines.v',ROOT/'common/photo_sd_cache.v',ROOT/'tests/reference/media_deadlines/photo_sd_cache_before.v',shell]
 h={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in files+[Path(__file__)]};start=time.monotonic();exe=out/'media.vvp';c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2005','-s','tb','-o',str(exe),*map(str,files)],cwd=ROOT,env=env,capture_output=True,text=True);log=c.stdout+c.stderr
 if not c.returncode:c=subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],cwd=out,env=env,capture_output=True,text=True,timeout=120);log+=c.stdout+c.stderr
 lp=out/'media_deadlines.log';lp.write_text(log);passed=c.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and 'ERROR:' not in log and all(sha(ROOT/k if not Path(k).is_absolute() else Path(k))==v for k,v in h.items())
 (out/'results.json').write_text(json.dumps([dict(test='media_deadlines',passed=passed,inputs_sha256=h,log=str(lp),log_sha256=sha(lp),seconds=round(time.monotonic()-start,2))],indent=2));print(log[-1500:],flush=True)
 if not passed:raise SystemExit(1)
if __name__=='__main__':main()
