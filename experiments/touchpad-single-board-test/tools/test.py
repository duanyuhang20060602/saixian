from pathlib import Path
import json,os,subprocess
ROOT=Path(__file__).resolve().parents[1]
iv=Path(os.environ.get('IVERILOG',str(ROOT.parent/'.tools/iverilog/bin/iverilog.exe')))
jobs={'tb_single':['rtl/touch_test_core.v','rtl/photo_touchpad.v','rtl/saixian_hmi_uart.v'],
      'tb_scene':['rtl/touch_test_scene.v']}
results=[]
for name,files in jobs.items():
 binary=ROOT/'tests'/(name+'.vvp')
 subprocess.run([str(iv),'-g2012','-s',name,'-o',str(binary),'tests/'+name+'.v',*files],cwd=ROOT,check=True)
 run=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=60)
 text=run.stdout+run.stderr;print(text,flush=True)
 (ROOT/'tests'/(name+'.log')).write_text(text)
 passed=run.returncode==0 and 'PASS' in text and 'FATAL' not in text
 results.append(dict(test=name,passed=passed))
 (ROOT/'tests/results.json').write_text(json.dumps(results,indent=2)+'\n')
 if not passed:raise SystemExit(1)
