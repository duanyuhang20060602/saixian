"""Prove incremental coordinates and elastic two-board transfer against independent oracles."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,struct,subprocess,time,zlib
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('E:/Codex/Work/cooperate-research-20261020/tests')
JOBS={'research_raster':['tests/tb_research_raster.v','common/photo_raster_delay.v']}
for mode in range(4):
 for stress in (0,1):JOBS[f'link_m{mode}_s{stress}']=['tests/tb_research_link.v','common/photo_link.v']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--only',nargs='+',choices=JOBS);ap.add_argument('--jobs',type=int,default=3);a=ap.parse_args()
 OUT.mkdir(parents=True,exist_ok=True)
 crc={}
 for words in (460800,691200):
  data=b''.join(struct.pack('>I',((i*0x01020305)^0x97a46b5d)&0xffffffff) for i in range(words));crc[words]=zlib.crc32(data)
 env=os.environ.copy();temp=Path('E:/Codex/Temp/cooperate-research-20261020');temp.mkdir(parents=True,exist_ok=True)
 env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 def run(name):
  started=time.monotonic();files=[ROOT/p for p in JOBS[name]]
  hashes={p.relative_to(ROOT).as_posix():digest(p) for p in files+[Path(__file__)]}
  options=[]
  if name.startswith('link_'):
   mode,stress=map(int,re.fullmatch(r'link_m(\d)_s(\d)',name).groups())
   options=['-P',f'tb.MODE={mode}','-P',f'tb.STRESS={stress}','-P',f'tb.EXPECTED_CRC=32\'h{crc[460800 if mode==0 else 691200]:08x}']
  binary=OUT/(name+'.vvp')
  r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb',*options,'-o',str(binary),*map(str,files)],cwd=OUT,env=env,capture_output=True,text=True)
  log=r.stdout+r.stderr
  if not r.returncode:
   r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=OUT,env=env,capture_output=True,text=True,timeout=900);log+=r.stdout+r.stderr
  (OUT/(name+'.log')).write_text(log,encoding='utf-8')
  unchanged=all(digest(ROOT/p)==h for p,h in hashes.items())
  passed=r.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
  record=dict(test=name,passed=passed,inputs_unchanged=unchanged,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,log_sha256=digest(OUT/(name+'.log')))
  if name.startswith('link_'):
   record['measurements']=[dict(mode=int(m),stress=int(s),prefetch=int(f),words=int(w),cycles=int(c),crc32=h) for m,s,f,w,c,h in re.findall(r'MEASURE mode=(\d) stress=(\d) prefetch=(\d) words=(\d+) cycles=(\d+) crc=([0-9a-f]+)',log)]
  print(name+': '+next((s for s in log.splitlines() if s.startswith('PASS ')),log[-2500:]),flush=True);return record
 selected=a.only or list(JOBS)
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:records=list(pool.map(run,selected))
 report=OUT/'results.json';previous=json.loads(report.read_text()) if report.exists() and a.only else []
 previous=[r for r in previous if r['test'] not in selected]
 report.write_text(json.dumps(previous+records,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in records):raise SystemExit('Research optimization verification failed')
if __name__=='__main__':main()
