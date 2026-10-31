from pathlib import Path
import argparse,hashlib,json,subprocess,shutil
ROOT=Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--out',type=Path,required=True);args=a.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
names=['tests/tb_fpga_rank_transport.v','tests/reference/match_single/photo_cached_control_before_match.v','tests/serial_title_ram_model.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v','common/photo_serial_text.v','common/match/photo_serial_text_runtime.v','common/photo_scan_font_index.v','common/photo_scan_glyph_b.v','common/saixian_hmi_uart.v','common/audio_ui/saixian_font_rom.v','common/saixian_battle_result_fx_pipelined.v','common/match/photo_match_control.v','common/match/photo_match_serial.v','common/match/photo_match_manager.v']
files=[ROOT/p for p in names];assets=[ROOT/'common'/p for p in ['photo_rank_header.hex','photo_rank_glyphs.hex','photo_rank_columns.hex']]
for p in assets:shutil.copy2(p,out/p.name)
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__),*files,*assets]};binary=out/'run.vvp';iv=Path('C:/iverilog/bin/iverilog.exe')
r=subprocess.run([str(iv),'-g2012','-DRANK_SIM','-DVICTORY_SIM','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=240);log+=r.stdout+r.stderr
(out/'run.log').write_text(log);print(log[-3000:],flush=True)
passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
record=dict(test='fpga_rank_transport',passed=passed,inputs_sha256=hashes,log=str(out/'run.log'),log_sha256=hashlib.sha256((out/'run.log').read_bytes()).hexdigest())
(out/'results.json').write_text(json.dumps([record],indent=2)+'\n');assert passed
