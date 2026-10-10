from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_delta_tests');WORK.mkdir(parents=True,exist_ok=True)
binary=WORK/'axis.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_axis','-o',str(binary),
               'src/user_source/hdl_source/video_rgb_to_axis_640x480.v','tests/tb_axis.v'],cwd=ROOT,check=True)
result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,capture_output=True,text=True)
(WORK/'axis.log').write_text(result.stdout+result.stderr)
print(result.stdout)
if result.returncode:raise RuntimeError('axis simulation failed')
