"""Stress the production renderer/arbiter transaction routing across modes."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, time
ROOT=Path(__file__).resolve().parents[1]
FILES=['tests/tb_relief_render_cdc.v','common/photo_award_render.v','common/photo_award_memory.v']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,default=Path('E:/Codex/Work/saixian-relief-render-tests'));a=ap.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    temp=out/'temp';temp.mkdir(exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
    files=[ROOT/f for f in FILES];hashes={p.relative_to(ROOT).as_posix():digest(p) for p in files+[Path(__file__)]}
    started=time.monotonic();log='';cases=[]
    for phase in (0,1700,4900):
        for latency in (1,3,12,27):
            binary=out/f'render_{phase}_{latency}.vvp'
            p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-P',f'tb.PHASE_PS={phase}','-P',f'tb.RESPONSE_CLOCKS={latency}','-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True)
            case_log=p.stdout+p.stderr
            if p.returncode==0:
                p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=60)
                case_log+=p.stdout+p.stderr
            passed=p.returncode==0 and 'PASS ' in case_log and not re.search(r'(?im)^(ERROR:|FATAL:)',case_log)
            log+=case_log;cases.append({'phase_ps':phase,'response_clocks':latency,'passed':passed})
            print(next((line for line in case_log.splitlines() if line.startswith('PASS ')),case_log),flush=True)
    path=out/'render_cdc.log';path.write_text(log,encoding='utf-8')
    unchanged=all(digest(ROOT/p)==h for p,h in hashes.items())
    result={'test':'render_cdc','passed':all(c['passed'] for c in cases) and unchanged,'inputs_unchanged':unchanged,
            'seconds':round(time.monotonic()-started,2),'inputs_sha256':hashes,'log_sha256':digest(path),'cases':cases,
            'scope':'Production photo_award_render plus photo_award_memory; players/video effect are interface stubs. Logical CDC/owner routing proof, not analog metastability simulation.'}
    (out/'results.json').write_text(json.dumps([result],indent=2)+'\n',encoding='utf-8')
    if not result['passed']:raise SystemExit('Renderer CDC regression failed')
if __name__=='__main__':main()
