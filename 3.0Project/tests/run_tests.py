from pathlib import Path
import subprocess, sys, struct, shutil
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from encode_delta import prepare
WORK=Path('E:/Codex/Temp/saixian_softflow720_tests');WORK.mkdir(parents=True,exist_ok=True)
blob=prepare()
words=struct.unpack('<'+'I'*(len(blob)//4),blob)
(WORK/'package_words.hex').write_text('\n'.join(f'{v:08x}' for v in words)+'\n')
# package hex was written by prepare()
tests=[('decoder',['src/user_source/hdl_source/delta_decoder.v','tests/tb_decoder.v'],
        [f'+package={(WORK/"package_words.hex").as_posix()}',f'+folder={WORK.as_posix()}']),
       ('loader',['src/user_source/hdl_source/delta_loader.v','tests/tb_loader.v'],
        [f'+package={(WORK/"package_bytes.hex").as_posix()}'])]
for name,sources,args in tests:
 binary=WORK/f'{name}.vvp'
 subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s',f'tb_{name}','-o',str(binary),*sources],cwd=ROOT,check=True)
 result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),*args],cwd=ROOT,capture_output=True,text=True)
 (WORK/f'{name}.log').write_text(result.stdout+result.stderr)
 print(result.stdout,flush=True)
 if result.returncode:raise RuntimeError(name+' failed: '+result.stderr)
