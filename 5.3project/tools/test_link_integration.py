"""Check abort flushing and production eRAM preprocessing with the prefetched sender."""
from pathlib import Path
import concurrent.futures,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('E:/Codex/Work/cooperate-research-20261020/integration-tests')
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
JOBS={'link_abort':['tests/tb_research_link_abort.v','common/photo_link.v']}
for mode in (0,1):
 JOBS[f'processing_link_{mode}']=['tests/tb_research_processing_link.v','common/photo_link.v','common/photo_b_processing.v',
  'tests/reference/award_v5/photo_b_processing.v','common/photo_processing.v','common/photo_color_format.v','common/fluid/water_pack.v','common/photo_audio_link.v','tests/ip_vendor_ram_adapter.v']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 OUT.mkdir(parents=True,exist_ok=True);(OUT/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n')
 env=os.environ.copy();temp=Path('E:/Codex/Temp/cooperate-research-20261020');env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 def run(name):
  start=time.monotonic();sources=[ROOT/p for p in JOBS[name]]
  hashes={p.relative_to(ROOT).as_posix():digest(p) for p in sources+[Path(__file__)]}
  external={};extra=[]
  if name!='link_abort':
   sources.append(VENDOR);external[str(VENDOR)]=digest(VENDOR);extra=['-P',f'tb.MODE={name[-1]}']
  binary=OUT/(name+'.vvp')
  r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-I',str(OUT),'-s','tb',*extra,'-o',str(binary),*map(str,sources)],cwd=OUT,env=env,capture_output=True,text=True)
  log=r.stdout+r.stderr
  if not r.returncode:
   r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=OUT,env=env,capture_output=True,text=True,timeout=900);log+=r.stdout+r.stderr
  (OUT/(name+'.log')).write_text(log,encoding='utf-8')
  unchanged=all(digest(ROOT/p)==h for p,h in hashes.items()) and all(digest(Path(p))==h for p,h in external.items())
  passed=r.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
  print(name+': '+next((s for s in log.splitlines() if s.startswith('PASS ')),log[-2500:]),flush=True)
  return dict(test=name,passed=passed,inputs_unchanged=unchanged,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,
   external_inputs_sha256=external,stimuli_sha256={'ip_init_map.vh':digest(OUT/'ip_init_map.vh')},log_sha256=digest(OUT/(name+'.log')))
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:records=list(pool.map(run,JOBS))
 (OUT/'results.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in records):raise SystemExit('Link integration proof failed')
if __name__=='__main__':main()
