from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_softflow720_tests')
sources=['src/user_source/hdl_source/delta_decoder.v','src/user_source/hdl_source/delta_player.v','src/user_source/hdl_source/delta_memory.v','tests/tb_budget.v']
binary=WORK/'budget.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_budget','-o',str(binary),*sources],cwd=ROOT,check=True)
with (WORK/'budget.log').open('w') as log:
    result=subprocess.run(['C:/iverilog/bin/vvp.exe','-i',str(binary),f'+package={(WORK/"package_words.hex").as_posix()}',
                           f'+folder={WORK.as_posix()}'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
print((WORK/'budget.log').read_text())
if result.returncode:raise RuntimeError('budget simulation failed')
