"""Check early preparation, slot lifetime, cancellation and existing scanout contracts."""
from pathlib import Path
import hashlib,json,os,subprocess,time
from test_thumbnail import JOBS as ORIGINAL
ROOT=Path(__file__).resolve().parents[1]
IV=Path(os.environ.get('IVERILOG',str(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe')))
JOBS={
 'early':('tb_thumbnail_early',['tests/tb_thumbnail_early.v','common/photo_cached_control_a.v','common/photo_thumbnail.v','common/photo_uart.v'],['THUMBNAIL_SIM']),
 'early_cancel':('tb_thumbnail_early_cancel',['tests/tb_thumbnail_early_cancel.v','common/photo_thumbnail.v'],['THUMBNAIL_SIM']),
 **{k:ORIGINAL[k] for k in ('memory','overlay','phase','blanking','control','bandwidth565')},
 'timing_control':('tb_switch_timing_control',['tests/tb_switch_timing_control.v','common/photo_switch_timing.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v'],[]),
}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 out=ROOT/'tests/thumbnail_early_results';out.mkdir(exist_ok=True)
 results=[]
 for name,(top,files,defines) in JOBS.items():
  started=time.monotonic();binary=out/(name+'.vvp')
  compiled=subprocess.run([str(IV),'-g2012',*['-D'+d for d in defines],'-s',top,'-o',str(binary),*files],cwd=ROOT,capture_output=True,text=True)
  log=compiled.stdout+compiled.stderr
  if compiled.returncode==0:
   run=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600)
   log+=run.stdout+run.stderr;passed=run.returncode==0 and 'PASS ' in log and 'FATAL' not in log
  else:passed=False
  (out/(name+'.log')).write_text(log,encoding='utf-8');print(name+': '+log,flush=True)
  results.append({'test':name,'passed':passed,'seconds':round(time.monotonic()-started,2),'defines':defines,
                  'inputs_sha256':{p:digest(ROOT/p) for p in files}})
  (out/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
  if not passed:raise SystemExit(1)
if __name__=='__main__':main()
