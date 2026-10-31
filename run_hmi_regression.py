from pathlib import Path
import subprocess,os,json,hashlib,concurrent.futures,re
r=Path.cwd();out=r/'validation-hmi';out.mkdir(exist_ok=True);iv=(r/'../.tools/msys2-sim/ucrt64/bin/iverilog.exe').resolve();env=dict(os.environ);env['PATH']=str(iv.parent)+os.pathsep+env['PATH']
def run(name):
 files=[r/f'5.0project/tests/{name}.v',r/'5.0project/common/saixian_hmi_uart.v'];binary=out/(name+'.vvp')
 top=re.search(r'module (\w+)',files[0].read_text())[1]
 p=subprocess.run([str(iv),'-g2012','-s',top,'-o',str(binary),*map(str,files)],env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:p=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],env=env,capture_output=True,text=True,timeout=90);log+=p.stdout+p.stderr
 (out/(name+'.log')).write_text(log);print(name,log[-450:],flush=True);return {'test':name,'passed':p.returncode==0 and 'PASS' in log,'inputs_sha256':{str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}}
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:records=list(pool.map(run,['tb_hmi','tb_touch_uart_trim','tb_touch_uart_trim_75m']))
(out/'results.json').write_text(json.dumps(records,indent=2));assert all(t['passed'] for t in records)
