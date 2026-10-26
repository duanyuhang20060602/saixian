from pathlib import Path
import sys,subprocess,os,json
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from pitch_model import model
BIN=Path('D:/qiansai/.tools/iverilog-portable/ucrt64/bin')
os.environ['PATH']=str(BIN)+os.pathsep+os.environ.get('PATH','')
OUT=ROOT/'results';HDL=ROOT/'project/src/user_source/hdl_source'
rng=np.random.default_rng(20261019)
n=np.arange(50000)
source=np.column_stack([np.rint(24000*np.sin(2*np.pi*440*n/48000)),np.rint(22000*np.cos(2*np.pi*660*n/48000))]).astype(np.int64)
source[:4096]=rng.integers(-32768,32768,(4096,2))
source[4096:5000,1]=-source[4096:5000,0]
modes=np.zeros(50000,dtype=np.int64)
modes[4096:16000]=1;modes[16000:28000]=2;modes[28000:39000]=3;modes[39000:49000]=4
stim=OUT/'input.hex';mp=OUT/'modes.hex';out=OUT/'rtl_output.txt';exe=OUT/'pitch.vvp'
stim.write_text(''.join(f'{((int(r)&65535)<<16)|(int(l)&65535):08x}\n' for l,r in source))
mp.write_text(''.join(f'{x:x}\n' for x in modes))
exe.unlink(missing_ok=True)
cp=subprocess.run([str(BIN/'iverilog.exe'),'-g2012','-DVICTORY_SIM','-s','tb_pitch','-o',str(exe),str(ROOT/'tests/tb_pitch.v'),str(HDL/'saixian_audio_pitch.v')],capture_output=True,text=True)
(OUT/'compile.log').write_text(cp.stdout+cp.stderr)
assert 'error:' not in cp.stderr.lower() and exe.exists() and exe.stat().st_size>100,cp.stderr
if cp.returncode:print(f'NOTE compiler teardown exit {cp.returncode}; executing freshly generated VVP',flush=True)
cp=subprocess.run([str(BIN/'vvp.exe'),str(exe),f'+STIM={stim.as_posix()}',f'+MODES={mp.as_posix()}',f'+OUT={out.as_posix()}'],capture_output=True,text=True,timeout=480)
(OUT/'simulation.log').write_text(cp.stdout+cp.stderr)
assert cp.returncode==0 and 'PASS' in cp.stdout and 'ERROR:' not in cp.stdout,cp.stdout+cp.stderr
actual=np.loadtxt(out,dtype=np.int64);expected=model(source,modes,True)
if not np.array_equal(actual,expected):
    bad=np.argwhere(actual!=expected);i,c=bad[0]
    raise AssertionError((int(i),int(c),actual[i].tolist(),expected[i].tolist(),int(bad.shape[0])))
# Dry mode is bit-exact with the unchanged waveform after the fixed delay.
assert np.array_equal(actual[2400:4000,:2],source[2400-1183:4000-1183])
stats={'exact_stereo_outputs':len(actual),'max_integer_error':0,'bypass_delay_samples':1183,
       'bypass_delay_ms':1183/48,'modes_tested':5,'input_spacing_clocks':700,
       'clear_test_zero_samples':2400}
(OUT/'verification.json').write_text(json.dumps(stats,indent=2))
print(cp.stdout,flush=True)
print('PASS exact Python integer reference for all outputs, gain ramps, phase and ready; dry mode exact 1183-sample delay',flush=True)
