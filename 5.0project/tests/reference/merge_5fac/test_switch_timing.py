"""Run focused timing and cache-identity checks; retain logs and input hashes."""
from pathlib import Path
import hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
IV=Path(os.environ.get('IVERILOG',str(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe')))
JOBS={
 'tb_switch_timing':['tests/tb_switch_timing.v','common/photo_switch_timing.v'],
 'tb_switch_timing_control':['tests/tb_switch_timing_control.v','common/photo_switch_timing.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v'],
 'tb_thumbnail_control':['tests/tb_thumbnail_control.v','common/photo_cached_control_a.v','common/photo_uart.v'],
}
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 out=ROOT/'tests/switch_timing_results';out.mkdir(exist_ok=True)
 results=[]
 for name,files in JOBS.items():
  began=time.monotonic();exe=out/(name+'.vvp')
  build=subprocess.run([str(IV),'-g2012','-s',name,'-o',str(exe),*files],cwd=ROOT,capture_output=True,text=True)
  (out/(name+'_compile.log')).write_text(build.stdout+build.stderr,encoding='utf-8')
  if build.returncode:raise SystemExit(build.stdout+build.stderr)
  run=subprocess.run([str(IV.with_name('vvp.exe')),str(exe)],cwd=ROOT,capture_output=True,text=True,timeout=90)
  log=run.stdout+run.stderr;(out/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
  result={'test':name,'passed':run.returncode==0 and 'PASS' in log and 'FATAL' not in log,
          'seconds':round(time.monotonic()-began,2),'inputs_sha256':{p:digest(ROOT/p) for p in files}}
  results.append(result);(out/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
  if not result['passed']:raise SystemExit(name+' failed')
if __name__=='__main__':main()
