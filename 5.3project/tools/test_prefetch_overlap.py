"""Prove overlap benefit against unchanged policy and re-run lock/pin/retry checks."""
from pathlib import Path
import hashlib,json,os,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
IV=Path(os.environ.get('IVERILOG',str(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe')))
FILES=['tests/tb_two_slot_cache.v','common/photo_sd_cache.v','common/photo_color_format.v','common/photo_audio_link.v',
       'common/photo_sd_audio_stream.v','common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 out=ROOT/'tests/prefetch_overlap_results';out.mkdir(exist_ok=True)
 (out/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n',encoding='utf-8')
 original=(ROOT/FILES[0]).read_text(encoding='utf-8')
 variant=out/'tb_two_slot_early.v'
 variant.write_text(original.replace('.FORWARD_ONLY(1)) dut(','.FORWARD_ONLY(1),.EARLY_PREFETCH(1)) dut('),encoding='utf-8')
 assert 'EARLY_PREFETCH(1)' in variant.read_text(encoding='utf-8')
 jobs=[('compare','tb_prefetch_overlap',[ROOT/'tests/tb_prefetch_overlap.v',*[ROOT/p for p in FILES]]),
       ('baseline_safety','tb',[ROOT/p for p in FILES]),
       ('early_safety','tb',[variant,*[ROOT/p for p in FILES[1:]]])]
 results=[]
 for name,top,files in jobs:
  started=time.monotonic();binary=out/(name+'.vvp')
  build=subprocess.run([str(IV),'-g2012','-DVICTORY_SIM','-DWATER_SIM','-I'+str(out),'-s',top,'-o',str(binary),*map(str,files)],cwd=ROOT,capture_output=True,text=True)
  log=build.stdout+build.stderr
  if build.returncode==0:
   run=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=60)
   log+=run.stdout+run.stderr;passed=run.returncode==0 and 'PASS ' in log and 'FATAL' not in log
  else:passed=False
  (out/(name+'.log')).write_text(log,encoding='utf-8');print(name+': '+log,flush=True)
  evidence=[Path(__file__),ROOT/'tests/tb_prefetch_overlap.v',ROOT/FILES[0],out/'ip_init_map.vh',*files]
  results.append({'test':name,'passed':passed,'seconds':round(time.monotonic()-started,2),
                  'inputs_sha256':{p.relative_to(ROOT).as_posix():digest(p) for p in evidence}})
  (out/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
  if not passed:raise SystemExit(1)
if __name__=='__main__':main()
