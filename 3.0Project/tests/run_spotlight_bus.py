from pathlib import Path
import subprocess,struct
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_spotlight_tests');WORK.mkdir(parents=True,exist_ok=True)
blob=(ROOT/'examples/TF卡素材/AWARD720.DLT').read_bytes()
hexfile=WORK/'package_bus.hex'
hexfile.write_text('\n'.join(f'{v:08x}' for v in struct.unpack('<'+'I'*(len(blob)//4),blob))+'\n')
binary=WORK/'spotlight_bus.vvp'
sources=['src/user_source/hdl_source/'+x for x in ['spotlight_player.v','delta_memory.v','delta_video.v','IP/afifo_16_32_256.v','IP/afifo_32_16_256.v']]+['tests/tb_spotlight_bus.v']
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_spotlight_bus','-o',str(binary),*sources],cwd=ROOT,check=True)
with (WORK/'spotlight_bus.log').open('w') as log:
 r=subprocess.run(['C:/iverilog/bin/vvp.exe','-i',str(binary),f'+package={hexfile.as_posix()}',f'+words={len(blob)//4}'],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
text=(WORK/'spotlight_bus.log').read_text();print(text,flush=True)
if r.returncode or 'PASS' not in text:raise RuntimeError('Rolling SDRAM arbitration test failed')
