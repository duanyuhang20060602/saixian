from pathlib import Path
import subprocess,time,json,hashlib
R=Path(__file__).resolve().parents[1];O=R/'tests/results'
IV=Path('C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe')
shared=['tests/tb_rgb888_bandwidth.v',*[f'projects/board_a/src/user_source/hdl_source/IP/{n}' for n in ['afifo_32_16_256.v','afifo_16_32_256.v']]]
report=[]
for baseline in [True,False]:
 name='rgb888_bandwidth_'+('before' if baseline else 'after')
 base='tests/reference/rgb888_switch_before/' if baseline else 'projects/board_a/src/user_source/hdl_source/SD/'
 sources=shared+[base+n for n in ['frame_read_write.v','frame_fifo_read.v','frame_fifo_write.v']]
 binary=O/(name+'.vvp');start=time.monotonic()
 subprocess.run([str(IV),'-g2012',*(['-DEXPECT_BASELINE_FAILURE'] if baseline else []),'-s','tb_rgb888_bandwidth','-o',str(binary),*sources],cwd=R,check=True)
 with (O/(name+'.log')).open('w') as f:p=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=1200)
 log=(O/(name+'.log')).read_text();print(log,flush=True)
 passed=p.returncode==0 and 'PASS' in log and 'FATAL' not in log
 report.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2),source_sha256={s:hashlib.sha256((R/s).read_bytes()).hexdigest() for s in sources}))
 (O/'rgb888_bandwidth_results.json').write_text(json.dumps(report,indent=2)+'\n')
 if not passed:raise SystemExit(1)
