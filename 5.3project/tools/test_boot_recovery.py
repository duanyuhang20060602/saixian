from pathlib import Path
import hashlib,json,subprocess,time
R=Path(__file__).resolve().parents[1];O=R/'tests/results'
IV=Path('C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe')
sources=['tests/tb_photo_receive_recovery.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v','common/saixian_transition.v']
start=time.monotonic();binary=O/'tb_photo_receive_recovery.vvp'
subprocess.run([str(IV),'-g2012','-s','tb_photo_receive_recovery','-o',str(binary),*sources],cwd=R,check=True)
with (O/'tb_photo_receive_recovery.log').open('w') as f:p=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=R,stdout=f,stderr=subprocess.STDOUT,timeout=600)
log=(O/'tb_photo_receive_recovery.log').read_text();print(log,flush=True)
passed=p.returncode==0 and 'PASS' in log and 'FATAL' not in log
result=dict(test='tb_photo_receive_recovery',passed=passed,seconds=round(time.monotonic()-start,2),source_sha256={s:hashlib.sha256((R/s).read_bytes()).hexdigest() for s in sources})
(O/'boot_recovery_results.json').write_text(json.dumps(result,indent=2)+'\n')
if not passed:raise SystemExit(1)
