from pathlib import Path
import subprocess,struct,zlib
ROOT=Path(__file__).resolve().parents[1];WORK=Path('E:/Codex/Temp/saixian_softflow720_tests')
data=(ROOT/'examples/TF卡素材/AWARD720.DLT').read_bytes()[:2048]
words=struct.unpack('<512I',data)
path=WORK/'cache_test.hex';path.write_text('\n'.join(f'{v:08x}' for v in words))
crc=zlib.crc32(data[512:]);binary=WORK/'cache.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_cache','-o',str(binary),
               'src/user_source/hdl_source/delta_memory.v','src/user_source/hdl_source/delta_read_capture.v','src/user_source/hdl_source/IP/afifo_16_32_256.v','tests/tb_cache.v'],cwd=ROOT,check=True)
r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),f'+package={path.as_posix()}',f'+crc={crc:08x}'],cwd=ROOT,capture_output=True,text=True)
output=r.stdout+r.stderr
(WORK/'cache.log').write_text(output);print(r.stdout)
if r.returncode:raise RuntimeError('cache test failed')
data=(ROOT/'examples/TF卡素材/AWARD720.DLT').read_bytes()[:16384]
path=WORK/'upload_test.hex';path.write_text('\n'.join(f'{v:08x}' for v in struct.unpack('<4096I',data)))
binary=WORK/'upload_memory.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_upload_memory','-o',str(binary),
               'src/user_source/hdl_source/delta_memory.v','src/user_source/hdl_source/delta_read_capture.v','src/user_source/hdl_source/IP/afifo_16_32_256.v','tests/tb_upload_memory.v'],cwd=ROOT,check=True)
r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),f'+package={path.as_posix()}',f'+crc={zlib.crc32(data[512:]):08x}'],cwd=ROOT,capture_output=True,text=True)
(WORK/'cache.log').write_text(output+r.stdout+r.stderr);print(r.stdout)
if r.returncode:raise RuntimeError('native upload memory test failed')
cache_output=(WORK/'cache.log').read_text()
small_path=WORK/'cache_test.hex';small_crc=zlib.crc32((ROOT/'examples/TF卡素材/AWARD720.DLT').read_bytes()[512:2048])
for label,capture,fail in [('early_reproduction',0,1),('early_capture',1,0)]:
 binary=WORK/(label+'.vvp')
 subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_cache','-o',str(binary),
   '-Ptb_cache.EARLY_READ=1',f'-Ptb_cache.CAPTURE_READ={capture}',f'-Ptb_cache.EXPECT_EARLY_FAIL={fail}',
   'src/user_source/hdl_source/delta_memory.v','src/user_source/hdl_source/delta_read_capture.v','src/user_source/hdl_source/IP/afifo_16_32_256.v','tests/tb_cache.v'],cwd=ROOT,check=True)
 r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),f'+package={small_path.as_posix()}',f'+crc={small_crc:08x}'],cwd=ROOT,capture_output=True,text=True)
 cache_output+=label+'\n'+r.stdout+r.stderr
 (WORK/'cache.log').write_text(cache_output);print(label,r.stdout)
 if r.returncode:raise RuntimeError(label+' failed')
binary=WORK/'upload_early_capture.vvp'
subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb_upload_memory','-o',str(binary),
 '-Ptb_upload_memory.EARLY_CAPTURE=1','src/user_source/hdl_source/delta_memory.v','src/user_source/hdl_source/delta_read_capture.v',
 'src/user_source/hdl_source/IP/afifo_16_32_256.v','tests/tb_upload_memory.v'],cwd=ROOT,check=True)
r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),f'+package={path.as_posix()}',f'+crc={zlib.crc32(data[512:]):08x}'],cwd=ROOT,capture_output=True,text=True)
(WORK/'cache.log').write_text(cache_output+'native_upload_early_capture\n'+r.stdout+r.stderr);print('native_upload_early_capture',r.stdout)
if r.returncode:raise RuntimeError('native upload early capture failed')
