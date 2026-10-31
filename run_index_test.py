from pathlib import Path
import subprocess,os,json,hashlib
root=Path.cwd();out=root/'validation-indexed-title';out.mkdir(exist_ok=True)
names=['tests/tb_serial_title_index.v','tests/serial_title_ram_model.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v','common/photo_serial_text.v','common/photo_scan_font_index.v','common/photo_scan_glyph_b.v','common/saixian_hmi_uart.v','common/audio_ui/saixian_font_rom.v']
files=[root/'5.0project'/n for n in names];iv=(root/'../.tools/msys2-sim/ucrt64/bin/iverilog.exe').resolve();env=dict(os.environ);env['PATH']=str(iv.parent)+os.pathsep+env['PATH']
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
r=subprocess.run([str(iv),'-g2012','-s','tb','-o',str(out/'full.vvp'),*map(str,files)],env=env,capture_output=True,text=True);log=r.stdout+r.stderr
if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(out/'full.vvp')],env=env,cwd=out,capture_output=True,text=True,timeout=180);log+=r.stdout+r.stderr
(out/'full.log').write_text(log);passed=r.returncode==0 and 'PASS indexed' in log
(out/'result.json').write_text(json.dumps({'passed':passed,'inputs_sha256':hashes},indent=2));print(log);assert passed
