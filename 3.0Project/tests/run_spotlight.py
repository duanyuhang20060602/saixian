from pathlib import Path
import subprocess,struct,sys
ROOT=Path(__file__).resolve().parents[1]
WORK=Path('E:/Codex/Temp/saixian_spotlight_tests');WORK.mkdir(parents=True,exist_ok=True)
blob=(ROOT/'examples/TF卡素材/AWARD720.DLT').read_bytes()
words=len(blob)//4
hexfile=WORK/'package.hex'
hexfile.write_text('\n'.join(f'{v:08x}' for v in struct.unpack('<'+'I'*words,blob))+'\n')
for name,sources in {
 'spotlight':['src/user_source/hdl_source/spotlight_player.v','tests/tb_spotlight.v'],
 'single_plate':['src/user_source/hdl_source/delta_player.v','src/user_source/hdl_source/delta_decoder.v','tests/tb_single_plate.v']
}.items():
 binary=WORK/(name+'.vvp')
 subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_'+name,'-o',str(binary),*sources],cwd=ROOT,check=True)
 cases=range(4) if name=='spotlight' else [0]
 for bad in cases:
  args=[f'+package={hexfile.as_posix()}',f'+words={words}',f'+bad={bad}'] if name=='spotlight' else []
  result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),*args],cwd=ROOT,capture_output=True,text=True)
  text=result.stdout+result.stderr;(WORK/(name+f'_{bad}.log')).write_text(text,encoding='utf-8')
  print(text,flush=True)
  if result.returncode or 'PASS' not in text:raise RuntimeError(name+' validation failed')
