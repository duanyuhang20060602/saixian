"""Independent floating-point FFT oracle (not a copy of the RTL butterfly)."""
from pathlib import Path
import argparse, subprocess, sys, math
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'doc/tools'))
from generate_audio_visual_roms import edges

ROOT=Path(__file__).resolve().parents[1]

def run(work):
    work.mkdir(parents=True,exist_ok=True)
    target=work/'fft.vvp'
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DVICTORY_SIM','-s','tb_audio_visual_fft','-o',str(target),
        'tests/tb_audio_visual_fft.v','src/user_source/hdl_source/saixian_audio_visualizer.v'],cwd=ROOT,check=True)
    n=np.arange(1024)
    tone=lambda bin,amp: np.rint(amp*np.sin(2*np.pi*bin*n/1024)).astype(np.int64)
    zero=np.zeros(1024,dtype=np.int64)
    a=tone(21,18000)
    rng=np.random.default_rng(20261002)
    cases={
        'silence':(zero,zero), 'dc':(zero+12345,zero-23456),
        'single':(a,a), 'antiphase':(a,-a), 'left_only':(a,zero),
        'right_only':(zero,a), 'dual_tone':(tone(5,9000)+tone(147,8000),tone(43,16000)),
        'off_bin':(tone(21.37,20000),tone(21.37,20000)),
        'fullscale':(tone(64,32767),tone(320,32767)),
        'half_volume':(np.floor_divide(a,2),np.floor_divide(a,2)),
        'square':(np.where(n%32<16,32767,-32768),np.where(n%64<32,32767,-32768)),
        'impulse':(np.where(n==511,32767,0),np.where(n==512,-32768,0)),
        'noise':(rng.integers(-32768,32768,1024),rng.integers(-32768,32768,1024)),
    }
    results={}
    e=edges();window=.5-.5*np.cos(2*np.pi*n/1024)
    for name,(left,right) in cases.items():
        stim=work/f'{name}.hex';out=work/f'{name}.txt'
        stim.write_text(''.join(f'{((int(r)&65535)<<16)|(int(l)&65535):08x}\n' for l,r in zip(left,right)),encoding='ascii')
        cp=subprocess.run(['C:/iverilog/bin/vvp.exe',str(target),f'+STIM={stim.as_posix()}',f'+OUT={out.as_posix()}'],
            cwd=ROOT,text=True,capture_output=True)
        if cp.returncode: raise AssertionError(cp.stdout+cp.stderr)
        if 'ERROR:' in cp.stdout: raise AssertionError(cp.stdout)
        data=[s.split() for s in out.read_text().splitlines()]
        actual=np.array([int(s[3]) for s in data if s[:2]==['BIN','1']],dtype=np.float64)
        assert len(actual)==511,(name,len(actual))
        spectra=[]
        for samples in (left,right):
            dc=math.floor(float(samples.sum())/1024)
            centered=np.clip(samples-dc,-32768,32767)
            spectra.append(np.fft.rfft(centered*window)/1024)
        expected=(np.abs(spectra[0][1:512])**2+np.abs(spectra[1][1:512])**2)/2
        # Fixed /2 at each stage and Q15 rotation/window cause an absolute
        # floor; compare amplitudes with a conservative 12 signed-FFT-LSB bound.
        error=np.max(np.abs(np.sqrt(actual)-np.sqrt(expected)))
        assert error<12,(name,'FFT amplitude error',error)
        heights=[int(s[2]) for s in data if s[0]=='BAND']
        for band in range(32):
            energy=float(expected[e[band]-1:e[band+1]-1].mean())
            db=10*np.log10(max(energy,1e-30)*16/(32768**2))
            wanted=max(0,min(72,72+db))
            # Quantization close to the floor is excluded from dB calibration
            # assertions; silence/DC are checked exactly separately.
            if wanted>12: assert abs(heights[band]-wanted)<2.5,(name,band,heights[band],wanted)
        if name in ('silence','dc'): assert max(heights)==0 and max(actual)==0
        results[name]=(heights,actual)
        print(f'PASS {name}: max FFT amplitude error {error:.3f} LSB',flush=True)
    # Signed fixed-point rounding may differ by one displayed dB between
    # +tone and -tone. It must not cancel or lose the principal band.
    principal=int(np.argmax(results['single'][0]))
    assert abs(results['single'][0][principal]-results['antiphase'][0][principal])<=1
    peak=max(results['single'][0]);half=max(results['half_volume'][0])
    assert 5<=peak-half<=7,('half amplitude must drop ~6dB',peak,half)
    assert 2<=peak-max(results['left_only'][0])<=4
    print('PASS independent NumPy oracle: 13 signals, stereo cancellation protection, -6dB volume and -3dB single channel')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--work',type=Path,required=True)
    run(parser.parse_args().work)
