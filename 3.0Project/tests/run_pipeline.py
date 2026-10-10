from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_delta_tests')
sources=['src/user_source/hdl_source/delta_decoder.v','src/user_source/hdl_source/delta_player.v','src/user_source/hdl_source/delta_memory.v','src/user_source/hdl_source/delta_video.v',
         'src/user_source/hdl_source/IP/afifo_16_32_256.v','src/user_source/hdl_source/IP/afifo_32_16_256.v','tests/tb_pipeline.v']
binary=WORK/'pipeline.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_pipeline','-o',str(binary),*sources],cwd=ROOT,check=True)
with (WORK/'pipeline.log').open('w') as log:
    result=subprocess.run(['C:/iverilog/bin/vvp.exe','-i',str(binary),f'+package={(WORK/"package_words.hex").as_posix()}',
                           f'+folder={WORK.as_posix()}'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
print((WORK/'pipeline.log').read_text())
if result.returncode:raise RuntimeError('pipeline simulation failed')
