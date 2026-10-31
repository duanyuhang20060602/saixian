"""Current879 UART/SD font and compact8-byte HMI/SPI regression."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1];IV=Path('C:/iverilog/bin/iverilog.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--only',nargs='+');a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 jobs={
 'title_index_match':('tb',['tests/tb_match_title_index.v','tests/reference/match_single/photo_cached_control_before_match.v','tests/serial_title_ram_model.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v','common/photo_serial_text.v','common/photo_scan_font_index.v','common/photo_scan_glyph_b.v','common/saixian_hmi_uart.v','common/audio_ui/saixian_font_rom.v','common/match/photo_match_control.v','common/match/photo_match_serial.v','common/match/photo_match_manager.v']),
 'hmi_spi_compact':('tb_hmi_remote_spi',['tests/tb_hmi_spi_compact.v','common/photo_hmi_remote.v','common/photo_audio_link.v','common/photo_audio_spi_b_offload.v','common/photo_processing.v']),
 'hmi_uart':('tb_hmi',['tests/tb_hmi.v','common/saixian_hmi_uart.v'])}
 if a.only:
  assert set(a.only)<=set(jobs);jobs={k:jobs[k] for k in a.only}
 def run(item):
  name,(top,files)=item;d=out/name;d.mkdir(exist_ok=True);paths=[ROOT/p for p in files];hashes={p:sha(ROOT/p) for p in files};binary=d/'run.vvp'
  r=subprocess.run([str(IV),'-g2012','-DVICTORY_SIM','-s',top,'-o',str(binary),*map(str,paths)],capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:
   r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600);log+=r.stdout+r.stderr
  (d/'run.log').write_text(log);passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
  assert hashes=={p:sha(ROOT/p) for p in hashes};print(name+': '+log[-1800:],flush=True)
  return dict(test=name,passed=passed,inputs_sha256=hashes,log=str(d/'run.log'),log_sha256=sha(d/'run.log'))
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(run,jobs.items()))
 (out/'results.json').write_text(json.dumps(results,indent=2)+'\n');assert all(r['passed'] for r in results)
if __name__=='__main__':main()
