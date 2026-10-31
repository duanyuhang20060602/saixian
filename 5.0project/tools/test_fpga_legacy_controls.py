from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--out',type=Path,required=True);args=a.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
files=[ROOT/p for p in ['tests/tb_fpga_legacy_controls.v','common/saixian_hmi_uart.v','common/photo_unified_settings_controller.v','common/audio_ui/saixian_event_controller.v','common/audio_ui/saixian_osd_overlay.v']]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),*files]};binary=out/'run.vvp';iv=Path('C:/iverilog/bin/iverilog.exe')
r=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],capture_output=True,text=True,timeout=90);log+=r.stdout+r.stderr
(out/'run.log').write_text(log);print(log[-2400:],flush=True)
passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
record=dict(test='fpga_legacy_controls',passed=passed,inputs_sha256=hashes,log=str(out/'run.log'),log_sha256=hashlib.sha256((out/'run.log').read_bytes()).hexdigest())
(out/'results.json').write_text(json.dumps([record],indent=2)+'\n');assert passed
