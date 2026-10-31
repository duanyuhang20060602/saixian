"""Cycle-by-cycle equivalence against the original UART, including DIV=1."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--iverilog',type=Path,required=True);a=ap.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);iv=a.iverilog.resolve()
    env=dict(os.environ);env['PATH']=str(iv.parent)+os.pathsep+env['PATH']
    names=['tests/tb_uart_pipeline_exact.v','common/photo_uart.v','tests/reference/photo_uart_before.v'];paths=[ROOT/n for n in names]
    hashes={n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in zip(names,paths)}
    def run(job):
        div,pulse=job;binary=out/f'uart_{div}_{pulse}.vvp'
        r=subprocess.run([str(iv),'-g2012','-s','tb',f'-Ptb.DIV={div}',f'-Ptb.PULSE={pulse}','-o',str(binary),*map(str,paths)],env=env,capture_output=True,text=True);log=r.stdout+r.stderr
        if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],env=env,capture_output=True,text=True,timeout=600);log+=r.stdout+r.stderr
        (out/f'uart_{div}_{pulse}.log').write_text(log,encoding='utf-8');print(log[-700:],flush=True)
        return {'div':div,'pulse_payload':pulse,'passed':r.returncode==0 and 'PASS' in log and 'FATAL' not in log,'inputs_sha256':hashes}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(run,[(d,p) for d in [1,2,8,326,434] for p in [0,1]]))
    assert hashes=={n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in zip(names,paths)}
    (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8');assert all(x['passed'] for x in results)
if __name__=='__main__':main()
