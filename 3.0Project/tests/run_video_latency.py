from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_softflow720_tests')
binary=WORK/'video_latency.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_video_latency','-o',str(binary),
 'src/user_source/hdl_source/delta_video.v','src/user_source/hdl_source/award_fx.v','src/user_source/hdl_source/award_sprite_rom.v','tests/tb_video_latency.v'],cwd=ROOT,check=True)
with (WORK/'video_latency.log').open('w') as log:
 r=subprocess.run(['C:/iverilog/bin/vvp.exe','-i',str(binary)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
print((WORK/'video_latency.log').read_text())
if r.returncode:raise RuntimeError('RGB/control latency validation failed')
