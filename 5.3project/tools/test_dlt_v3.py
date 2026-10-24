from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
import json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'tests/results'
IV=Path('C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe')
subprocess.run([sys.executable,'tools/test_dlt.py','--prepare-only'],cwd=ROOT,check=True)
jobs={
 'tb_dlt_reader':['common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v','common/photo_color_format.v'],
 'tb_dlt_faults':['common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v'],
 'tb_dlt_cache':['tests/native_unused_bram.v','common/photo_sd_cache.v','common/photo_sd/bmp_read.v','common/photo_sd/saixian_media_header.v','common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v','common/photo_color_format.v'],
}
def run(name,sources):
 start=time.monotonic();binary=OUT/(name+'.vvp')
 subprocess.run([str(IV),'-g2012','-s',name,'-o',str(binary),'tests/'+name+'.v',*sources],cwd=ROOT,check=True,capture_output=True)
 r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=1800)
 log=r.stdout+r.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
 passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
 return dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2))
results=[]
with ThreadPoolExecutor(max_workers=3) as pool:
 for future in as_completed([pool.submit(run,n,s) for n,s in jobs.items()]):
  results.append(future.result())
  (OUT/'dlt_v3_engine_results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
if not all(v['passed'] for v in results):raise SystemExit(1)
