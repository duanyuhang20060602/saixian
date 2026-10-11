from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_softflow720_tests');WORK.mkdir(parents=True,exist_ok=True)
binary=WORK/'award_fx.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_award_fx','-o',str(binary),
    'src/user_source/hdl_source/award_fx.v','src/user_source/hdl_source/award_sprite_rom.v','tests/tb_award_fx.v'],cwd=ROOT,check=True)
r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,capture_output=True,text=True)
(WORK/'award_fx.log').write_text(r.stdout+r.stderr);print(r.stdout)
if r.returncode:raise RuntimeError('Live effect validation failed')
