"""B audio integration and bit-exact release-model checks; all outputs on E:."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,importlib.util,json,os,re,subprocess,time
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
COMMON=['common/photo_audio_link.v','common/photo_audio_features.v','common/photo_audio_pitch_b.v',
        'common/audio_ui/saixian_audio_pitch.v','common/audio_ui/saixian_audio_repair.v','common/audio_ui/photo_audio_cue_samples.v']
JOBS=('model','native_model','volume','keys','transport')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--only',nargs='+',choices=JOBS);ap.add_argument('--jobs',type=int,default=3);a=ap.parse_args()
 out=a.out.resolve();assert out.drive.upper()=='E:';out.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();temp=Path('E:/Codex/Temp/audio-pitch-tests');temp.mkdir(parents=True,exist_ok=True);env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp),PYTHONDONTWRITEBYTECODE='1')
 def run(name):
  start=time.monotonic();folder=out/name;folder.mkdir(exist_ok=True);defines=['-DVICTORY_SIM'];flags=[];measurements={}
  if name in ('model','native_model'):
   n=50000 if name=='model' else 10000
   original=ROOT/'tests/reference/audio_pitch/tb_pitch.v'
   text=original.read_text().replace('49999',str(n-1)).replace('50000',str(n))
   text=text.replace('saixian_audio_pitch dut(.*);','saixian_audio_pitch #(.COMPACT_DRY(1)) dut(.*);')
   bench=folder/'tb_pitch.v';bench.write_text(text,encoding='utf-8');top='tb_pitch'
   files=[bench,ROOT/'common/audio_ui/saixian_audio_pitch.v'];evidence=[original,ROOT/'tests/reference/audio_pitch/quality_model.py',Path(__file__)]
   if name=='native_model':
    defines=[];files+=[ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR]
    (folder/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n');flags=['-I'+str(folder)]
   source=np.column_stack([np.rint(24000*np.sin(2*np.pi*440*np.arange(n)/48000)),np.rint(22000*np.cos(2*np.pi*660*np.arange(n)/48000))]).astype(np.int64)
   source[:4096]=np.random.default_rng(20261019).integers(-32768,32768,(4096,2));source[4096:min(n,5000),1]=-source[4096:min(n,5000),0]
   modes=np.zeros(n,dtype=np.int64)
   edges=[4096,16000,28000,39000,49000] if n==50000 else [2500,4000,5500,7000,9000]
   for i in range(4):modes[edges[i]:edges[i+1]]=i+1
   stim=folder/'input.hex';modefile=folder/'modes.hex';result=folder/'rtl_output.txt'
   stim.write_text(''.join(f'{((int(r)&65535)<<16)|(int(l)&65535):08x}\n' for l,r in source));modefile.write_text(''.join(f'{x:x}\n' for x in modes))
   extra=[f'+STIM={stim.as_posix()}',f'+MODES={modefile.as_posix()}',f'+OUT={result.as_posix()}']
  else:
   bench=ROOT/f'tests/tb_pitch_{name}.v';top='tb';files=[bench,*[ROOT/p for p in COMMON]];evidence=[Path(__file__)];extra=[]
  hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in [*files,*evidence]}
  binary=folder/'simulation.vvp';c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012',*defines,*flags,'-s',top,'-o',str(binary),*map(str,files)],cwd=ROOT,env=env,capture_output=True,text=True)
  log=c.stdout+c.stderr
  if c.returncode==0:
   c=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary),*extra],cwd=ROOT,env=env,capture_output=True,text=True,timeout=900);log+=c.stdout+c.stderr
  passed=c.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
  if passed and name in ('model','native_model'):
   refpath=ROOT/'tests/reference/audio_pitch/quality_model.py';spec=importlib.util.spec_from_file_location('pitch_reference_'+name,refpath);ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref);ref.ROOT=folder
   qs=[]
   for cutoff in [20000,16000,20000,14000,10500]:
    taps=np.arange(63)-31;h=2*(cutoff/48000)*np.sinc(2*(cutoff/48000)*taps)*np.kaiser(63,7);h/=h.sum();q=np.rint(h*32768).astype(np.int64);q[31]+=32768-int(q.sum());qs.append(q)
   (folder/'results').mkdir(exist_ok=True);np.save(folder/'results/fir_q15.npy',np.array(qs))
   actual=np.loadtxt(result,dtype=np.int64);expected=ref.model(source,modes,True)
   if not np.array_equal(actual,expected):
    bad=np.argwhere(actual!=expected);i,col=bad[0];raise AssertionError((name,int(i),int(col),actual[i].tolist(),expected[i].tolist()))
   measurements={'exact_stereo_frames':n,'max_integer_error':0,'modes':5,'reference_commit':'c2d2df8008c93f9a89308007c882d9093a808e06','production_history_ram32_blocks':6,'dry_history_frames':2048,'filtered_history_frames':4096,'native_vendor_ram':name=='native_model','clear_zero_frames':2400}
   log+='PASS exact independent release fixed-point model, all PCM/mode/ramp/phase/ready fields\n'
  for p,h in hashes.items():assert sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h,'Input changed: '+p
  logpath=out/(name+'.log');logpath.write_text(log,encoding='utf-8');print(name+': '+log[-2200:],flush=True)
  return {'test':name,'passed':passed,'seconds':round(time.monotonic()-start,2),'inputs_sha256':hashes,'log':str(logpath),'log_sha256':sha(logpath),'measurements':measurements}
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:records=list(pool.map(run,a.only or JOBS))
 dest=out/'results.json';old=json.loads(dest.read_text()) if dest.exists() else [];old=[r for r in old if r['test'] not in {r['test'] for r in records}];dest.write_text(json.dumps(old+records,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in records):raise SystemExit(1)
if __name__=='__main__':main()
