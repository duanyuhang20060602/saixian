"""Real UART stable-payload contract and reconnect-boundary regression."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();env.update(TEMP=str(out),TMP=str(out),TMPDIR=str(out))
 reference=ROOT/'tests/reference/kind_before/photo_cached_control_a.v';meta=ROOT/'tests/reference/kind_before/source.json';old=reference.read_text(encoding='utf-8');m=json.loads(meta.read_text(encoding='utf-8'));assert hashlib.sha256(old.encode()).hexdigest()==m['original_normalized_sha256']
 expected=re.sub(r'\bkind==(\d+)(?![\w\'])',lambda q:'kind_match_q['+q[1]+']',old).replace('wire [7:0] kind=incoming[159:152];\n','wire [7:0] kind=incoming[159:152];\n'+m['decoder'],1)
 assert (ROOT/'common/photo_cached_control_a.v').read_text(encoding='utf-8')==expected,'Unexpected controller change outside packet-kind decode'
 files=[ROOT/p for p in ('tests/tb_relief_uart_contract.v','common/photo_cached_control_a.v','common/photo_uart.v')];evidence=files+[Path(__file__)]+[reference,meta]
 hashes={p.relative_to(ROOT).as_posix():sha(p) for p in evidence};started=time.monotonic();binary=out/'uart_contract.vvp'
 result=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True,cwd=out,env=env);log=result.stdout+result.stderr
 if result.returncode==0:
  result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],capture_output=True,text=True,cwd=out,env=env,timeout=300);log+=result.stdout+result.stderr
 path=out/'uart_contract.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(p)==hashes[p.relative_to(ROOT).as_posix()] for p in evidence)
 passed=result.returncode==0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
 record=dict(test='uart_contract',passed=passed,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,inputs_unchanged=unchanged,log=str(path),log_sha256=sha(path),scope='Real production UART TX/RX; local state/timer positioning only for deterministic reconnect/CRC collision.')
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n');print(next((s for s in log.splitlines() if s.startswith('PASS ')),log[-4500:]),flush=True)
 if not passed:raise SystemExit(1)
if __name__=='__main__':main()
