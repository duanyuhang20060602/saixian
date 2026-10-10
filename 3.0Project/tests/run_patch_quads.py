from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1];TEMP=Path('E:/Codex/Temp/saixian_delta_tests')
binary=TEMP/'patch_quads.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_patch_quads','-o',str(binary),
 'src/user_source/hdl_source/delta_memory.v','tests/tb_patch_quads.v'],cwd=ROOT,check=True)
r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,capture_output=True,text=True)
(TEMP/'patch_quads.log').write_text(r.stdout+r.stderr);print(r.stdout)
if r.returncode:raise RuntimeError('quad patch test failed')
# This is an external saved revision, intentionally outside the delivered tree.
legacy=Path('E:/Codex/Work/saixian_official_materials/delta_memory_before_quad_write.v')
if legacy.exists():
 binary=TEMP/'patch_legacy_rejection.vvp'
 subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DLEGACY_MEMORY','-s','tb_patch_quads',
  '-o',str(binary),str(legacy),'tests/tb_patch_quads.v'],cwd=ROOT,check=True)
 r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,capture_output=True,text=True)
 (TEMP/'patch_legacy_rejection.log').write_text(r.stdout+r.stderr)
 if not r.returncode or 'four-word patch requires four beats' not in r.stdout:raise RuntimeError('old single-word protocol violation was not reproduced')
 print('PASS reproduction: original one-beat patch rejected by the APUG011 four-word contract check')
