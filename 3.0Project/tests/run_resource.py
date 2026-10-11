from pathlib import Path
import subprocess,struct,sys
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_spotlight_tests');WORK.mkdir(parents=True,exist_ok=True)
maps=(ROOT/'examples/TF卡素材/spotlight_maps.bin').read_bytes()
assert len(maps)==120*14400
assert all(not any(maps[i*14400+68*160:(i+1)*14400]) for i in range(120))
sys.path.insert(0,str(ROOT/'tools'))
from resource_profile import HIGH_ROWS,HIGH_WORDS
assert len(HIGH_ROWS)==68 and HIGH_WORDS==377
for frame in range(120):
 for y,(base,first,count) in enumerate(HIGH_ROWS):
  for x in range(40):
   if not first<=x<first+count:
    assert all(v<128 for v in maps[frame*14400+y*160+x*4:frame*14400+y*160+x*4+4])
binary=WORK/'sprite_storage.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_sprite_storage','-o',str(binary),
 'src/user_source/hdl_source/award_sprite_rom.v','tests/tb_sprite_storage.v'],cwd=ROOT,check=True)
result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=ROOT,capture_output=True,text=True)
text=result.stdout+result.stderr;(WORK/'sprite_storage.log').write_text(text,encoding='utf-8')
print(text,flush=True)
if result.returncode or 'PASS' not in text:raise RuntimeError('Lossless sprite storage regression failed')
print('PASS resource asset profile: all 120 zero tails and sparse-MSB bounds verified; full sprite opacity/shade preserved')
