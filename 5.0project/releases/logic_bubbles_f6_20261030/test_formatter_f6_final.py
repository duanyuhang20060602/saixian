from pathlib import Path
import subprocess,os,json,hashlib,concurrent.futures
root=Path(__file__).resolve().parent;out=root/'validation-logic-f6-final';out.mkdir(exist_ok=True)
iv=(root/'../.tools/msys2-sim/ucrt64/bin/iverilog.exe').resolve();env=dict(os.environ);env['PATH']=str(iv.parent)+os.pathsep+env['PATH']
files=[root/n for n in ['5.0project/tests/tb_f6_formatter_bubbles.v','5.0project/common/photo_processing.v','5.0project/tests/reference/f6_logic/formatter_before.v']]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
def run(job):
 level,stall=job;name=f'formatter-{level}-{stall}';binary=out/(name+'.vvp')
 r=subprocess.run([str(iv),'-g2012','-s','tb',f'-Ptb.LEVEL={level}',f'-Ptb.STALL={stall}','-o',str(binary),*map(str,files)],env=env,capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],env=env,capture_output=True,text=True,timeout=120);log+=r.stdout+r.stderr
 passed=r.returncode==0 and 'PASS formatter' in log and 'FATAL' not in log
 (out/(name+'.log')).write_text(log,encoding='utf-8')
 print(name,passed,flush=True)
 return dict(test=name,passed=passed,inputs_sha256=hashes)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:records=list(pool.map(run,[(l,s) for l in range(16) for s in [0,1]]))
assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
(out/'results.json').write_text(json.dumps(records,indent=2)+'\n');assert all(r['passed'] for r in records)
