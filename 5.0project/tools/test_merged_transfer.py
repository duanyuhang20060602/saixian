"""Real FIFO and delayed-link checks for the merged photo transport."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 temp=Path('E:/Codex/Temp/saixian-merged-transfer-20261025');temp.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 ip='src/board_b/user_source/hdl_source/IP/'
 jobs={name:dict(top=top,paths=[tb,'common/photo_link.v']+[ip+n for n in fifo]) for name,top,tb,fifo in [
 ('merged_fifo_full','tb_real_fifo_link_full','tests/tb_real_fifo_link_full.v',['afifo_32_16_256.v','afifo_16_32_256.v']),
 ('merged_fifo_delay','tb_real_fifo_link_delay','tests/tb_real_fifo_link_delay.v',['afifo_32_16_256.v','afifo_16_32_256.v']),
 ('merged_link_timing','tb_link_timing','tests/tb_link_timing.v',[]),
 ('merged_link_abort','tb','tests/tb_research_link_abort.v',[]) ]}
 def run(name):
  job=jobs[name];work=out/name;work.mkdir(exist_ok=True);files=[ROOT/p for p in job['paths']];evidence=files+[Path(__file__)];hashes={p.relative_to(ROOT).as_posix():sha(p) for p in evidence};start=time.monotonic();binary=work/'sim.vvp'
  p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s',job['top'],'-o',str(binary),*map(str,files)],cwd=work,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
  if p.returncode==0:
   try:p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=work,env=env,capture_output=True,text=True,timeout=1800);log+=p.stdout+p.stderr
   except subprocess.TimeoutExpired:p=subprocess.CompletedProcess([],124);log+='\nTIMEOUT: no PASS claimed\n'
  path=work/(name+'.log');path.write_text(log,encoding='utf-8');unchanged=all(sha(ROOT/k)==v for k,v in hashes.items());passed=p.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
  print(name+': '+next((line for line in log.splitlines() if line.startswith('PASS ')),log[-2500:]),flush=True)
  return dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,inputs_unchanged=unchanged,log=str(path),log_sha256=sha(path))
 results=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  for r in pool.map(run,jobs):
   results.append(r);(out/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in results):raise SystemExit(1)
if __name__=='__main__':main()
