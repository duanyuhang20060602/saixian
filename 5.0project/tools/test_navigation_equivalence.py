"""Compare optimized navigation with the exact pre-change controller fixture."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 s=(ROOT/'tests/fx11_water/tb_protocol.v').read_text(encoding='utf-8')
 s=s.replace('photo_cached_control_a_reference #(', 'photo_cached_control_a_before #(')
 s=re.sub(r'\.(high_color|format_changed)\([^)]*\),?','',s)
 s=s.replace('actual_high_color!==reference_high_color || actual_format_changed!==reference_format_changed || ','')
 s=re.sub(r'\b(dut|reference)\.timer\b',r'\1.timer_count',s)
 s=s.replace('reference.state=selected','reference.state_flags=(16\'d1<<selected)')
 s=s.replace('PASS explicit onehot controller:', 'PASS unchanged navigation/control behavior:')
 (out/'navigation.v').write_text(s,encoding='ascii')
 files=[out/'navigation.v',ROOT/'common/photo_cached_control_a.v',ROOT/'common/photo_uart.v',ROOT/'tests/reference/complete_boot/photo_cached_control_a.v']
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
 iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe';binary=out/'navigation.vvp'
 r=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=300);log+=r.stdout+r.stderr
 (out/'navigation.log').write_text(log,encoding='utf-8');print(log[-2500:],flush=True)
 assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
 passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
 (out/'results.json').write_text(json.dumps({'passed':passed,'inputs_sha256':hashes},indent=2),encoding='utf-8');assert passed
if __name__=='__main__':main()
