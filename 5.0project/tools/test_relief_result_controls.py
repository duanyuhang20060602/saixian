"""Production top control-register wiring plus the real result FSM."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 temp=out/'temp';temp.mkdir(exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 text=(ROOT/'common/top_photo_a.v').read_text();shells={}
 for m in re.finditer(r'^\s*([a-z]\w*_\w+)\s*(?:#\((.*?)\))?\s+(\w+)\s*\((.*?)\);',text,re.M|re.S):
  module,params,instance,ports=m.groups()
  if module in ('module','saixian_battle_result_fx'):continue
  names=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',ports)));parameters=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',params or '')))
  if module in shells:
   names=list(dict.fromkeys(re.findall(r'input (\w+)',shells[module])+names));parameters=list(dict.fromkeys(re.findall(r'parameter (\w+)',shells[module])+parameters))
  if names:shells[module]='module '+module+(' #('+','.join('parameter '+p+'=0' for p in parameters)+')' if parameters else '')+'('+','.join('input '+p for p in names)+'); endmodule'
 shell=out/'hardware_shells.v';shell.write_text('\n'.join(shells.values()))
 source=ROOT/'common/saixian_battle_result_fx_pipelined.v'
 ref=out/'reference_result_fx.v';ref.write_text(source.read_text().split('module saixian_red_victory_atlas',1)[0].replace('module saixian_battle_result_fx(','module reference_result_fx(',1))
 files=[ROOT/'tests/tb_relief_result_controls.v',ROOT/'common/top_photo_a.v',source,shell,ref]
 evidence=files+[Path(__file__),*(ROOT/'src/board_a/user_source/hdl_source').glob('*.hex')]
 hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
 started=time.monotonic();binary=out/'result_controls.vvp'
 p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DVICTORY_SIM','-s','tb','-o',str(binary),*map(str,files)],cwd=ROOT,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,env=env,capture_output=True,text=True,timeout=120);log+=p.stdout+p.stderr
 path=out/'result_controls.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(q)==hashes[q.relative_to(ROOT).as_posix() if q.is_relative_to(ROOT) else str(q)] for q in evidence)
 passed=p.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
 result=dict(test='result_controls',passed=passed,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,inputs_unchanged=unchanged,log=str(path),log_sha256=sha(path),scope='Actual production top and result FSM; hardware shells omit unrelated blocks. Same qualified event trace shifted one clock; raw busy feedback window settles one clock later.')
 (out/'results.json').write_text(json.dumps([result],indent=2)+'\n',encoding='utf-8');print(next((s for s in log.splitlines() if s.startswith('PASS ')),log[-3500:]),flush=True)
 if not passed:raise SystemExit('Result controls failed')
if __name__=='__main__':main()
