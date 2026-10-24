from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 files=[ROOT/p for p in ['tests/tb_native_relief_cache.v','common/photo_cached_control_a.v','common/photo_uart.v']];evidence=files+[Path(__file__)];hashes={p.relative_to(ROOT).as_posix():sha(p) for p in evidence};env=os.environ.copy();env.update(TEMP=str(out),TMP=str(out),TMPDIR=str(out));started=time.monotonic();binary=out/'cache.vvp'
 p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=60);log+=p.stdout+p.stderr
 logfile=out/'native_cache.log';logfile.write_text(log,encoding='utf-8');unchanged=all(sha(p)==hashes[p.relative_to(ROOT).as_posix()] for p in evidence);passed=p.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
 record=dict(test='native_cache',passed=passed,inputs_unchanged=unchanged,inputs_sha256=hashes,log=str(logfile),log_sha256=sha(logfile),seconds=round(time.monotonic()-started,2),scope='Real production controller planner; scheduler held at WAIT_CONTEXT and accepted cache metadata positioned deterministically. UART/transport tested separately.')
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit(1)
if __name__=='__main__':main()
