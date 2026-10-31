from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
original=ROOT/'tests/tb_match_serial.v';s=original.read_text().replace('wire bad,legacy_start;', 'wire bad,legacy_start,timeout;')
s=s.replace('.text_active(old_text),.text_can_start(idle)', '.text_active(old_text || busy),.text_timeout(timeout),.text_can_start(idle)')
s=s.replace('#(.HZ(2000),.DB_CYCLES(3),.HOLD_CYCLES(100))', '#(.HZ(2000),.DB_CYCLES(3),.HOLD_CYCLES(100),.SHARED_TIMEOUT(1))')
s=s.replace('.serial_idle(idle),.text_active(old_text),', '.serial_idle(idle),.text_active(old_text),.serial_timeout(timeout),')
bench=out/'bench.v';bench.write_text(s)
files=[bench,*[ROOT/p for p in ['common/saixian_hmi_uart.v','common/match/photo_match_serial.v','common/match/photo_match_manager.v','common/match/photo_match_control.v']]]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),original,*files]};binary=out/'run.vvp';iv=Path('C:/iverilog/bin/iverilog.exe')
r=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=90);log+=r.stdout+r.stderr
(out/'run.log').write_text(log);print(log[-2200:],flush=True);passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
record=dict(test='shared_hmi_timeout',passed=passed,inputs_sha256=hashes,log=str(out/'run.log'),log_sha256=hashlib.sha256((out/'run.log').read_bytes()).hexdigest())
(out/'results.json').write_text(json.dumps([record],indent=2)+'\n');assert passed
