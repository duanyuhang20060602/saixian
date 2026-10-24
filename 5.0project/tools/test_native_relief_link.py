from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time,zlib,concurrent.futures
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);env=os.environ.copy();env.update(TEMP=str(out),TMP=str(out),TMPDIR=str(out))
 files=[ROOT/'tests/tb_native_relief_link.v',ROOT/'common/photo_link.v'];evidence=files+[Path(__file__)];hashes={p.relative_to(ROOT).as_posix():sha(p) for p in evidence}
 def run(kind):
  words=985088 if kind==2 else 691200;folder=out/str(kind);folder.mkdir(exist_ok=True);start=time.monotonic();values=(np.arange(words,dtype=np.uint32)*np.uint32(0x045d9f3b))^np.uint32(0x96ac37e1);crc=zlib.crc32(values.astype('>u4').tobytes());fixture=folder/'expected_crc.hex';fixture.write_text(f'{crc:08x}\n',encoding='ascii');binary=folder/'link.vvp'
  p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-P',f'tb.KIND={kind}','-P',f'tb.WORDS={words}','-o',str(binary),*map(str,files)],cwd=folder,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
  if p.returncode==0:
   p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=folder,env=env,capture_output=True,text=True,timeout=1200);log+=p.stdout+p.stderr
  saved=folder/'native_link.log';saved.write_text(log,encoding='utf-8');ok=p.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log);print(next((s for s in log.splitlines() if s.startswith('PASS ')),log[-3000:]),flush=True)
  return dict(kind=kind,words=words,passed=ok,seconds=round(time.monotonic()-start,2),log=str(saved),log_sha256=sha(saved),crc32=crc)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:cases=list(pool.map(run,[0,1,2]))
 unchanged=all(sha(ROOT/p)==h for p,h in hashes.items());passed=all(c['passed'] for c in cases) and unchanged;log=out/'native_link.log';log.write_text(''.join(Path(c['log']).read_text(encoding='utf-8') for c in cases),encoding='utf-8');record=dict(test='native_link',passed=passed,inputs_sha256=hashes,inputs_unchanged=unchanged,log=str(log),log_sha256=sha(log),cases=cases)
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8')
 if not passed:raise SystemExit('Native link regression failed')
if __name__=='__main__':main()
