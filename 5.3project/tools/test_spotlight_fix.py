"""Verify SDRAM award alignment through B's real wrapper, FIFOs and link."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,shutil,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
DEFAULT=Path('E:/Codex/Work/cooperate-spotlight-fix-20261020/tests')
BASELINE=ROOT/'tests/reference/before_spotlight/result.json'
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_logic_dram.v')
FIXTURES=ROOT/'tests/vectors/award_v5'
B='src/board_b/user_source/hdl_source/'
JOBS=('original_corruption','sdram_link_565','sdram_link_888','native_midframe')
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,default=DEFAULT)
    ap.add_argument('--baseline',type=Path,default=BASELINE)
    ap.add_argument('--only',nargs='+',choices=JOBS);ap.add_argument('--jobs',type=int,default=2);a=ap.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
    record=json.loads(a.baseline.read_text());old=(a.baseline.parent/record['work_project']).resolve()/B/'frame_store.v'
    assert digest(old)==record['inputs_sha256'][B+'frame_store.v']
    shutil.copy2(old,out/'board_b_frame_store_before.v')
    for f in ('award_expected.hex','light_tail.hex'):shutil.copy2(FIXTURES/f,out/f)
    model=out/'vendor_logic_dram_functional.v'
    model.write_text(VENDOR.read_text().split('`pragma protect begin_protected',1)[0],encoding='utf-8')
    native=out/'photo_spotlight_player_native.v'
    native.write_text((ROOT/'common/photo_spotlight_player.v').read_text().replace('`ifdef WATER_SIM','`ifdef AWARD_BOTTOM_FALLBACK'),encoding='utf-8')
    stimuli={p.name:digest(p) for p in out.glob('*.hex')}
    env=os.environ.copy();temp=Path('E:/Codex/Temp/cooperate-spotlight-fix');temp.mkdir(parents=True,exist_ok=True)
    env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
    def run(name):
        start=time.monotonic();extra=[];external={};derived={};language='-g2012'
        if name=='native_midframe':
            names=['tests/tb_award_v5_startup.v','common/photo_spotlight_player.v','common/photo_award_memory.v']
            extra=['-P','tb.ENABLE_LINE=300','-P','tb.ENABLE_X=347'];language='-g2005'
        else:
            names=['tests/tb_award_v5_sdram_link.v',B+'frame_store.v',*[B+'SD/'+f for f in ('frame_read_write.v','frame_fifo_read.v','frame_fifo_write.v')],
                   *[B+'IP/'+f for f in ('afifo_32_16_256.v','afifo_16_32_256.v')],
                   'common/photo_link.v','common/photo_award_memory.v','common/photo_spotlight_player.v']
            extra=['-DWATER_SIM','-P','tb.EXPECT_CORRUPT='+str(int(name=='original_corruption')),'-P','tb.COLOR='+str(int(name=='sdram_link_888'))]
        evidence=[ROOT/n for n in names]+[Path(__file__)]
        hashes={p.relative_to(ROOT).as_posix():digest(p) for p in evidence}
        sources=[ROOT/n for n in names]
        if name=='original_corruption':
            sources=[out/'board_b_frame_store_before.v' if p==ROOT/B/'frame_store.v' else p for p in sources]
            external={str(a.baseline):digest(a.baseline),str(old):digest(old)}
            derived['board_b_frame_store_before.v']=digest(out/'board_b_frame_store_before.v')
        if name=='native_midframe':
            sources=[native if p.name=='photo_spotlight_player.v' else p for p in sources]+[model]
            external={str(VENDOR):digest(VENDOR)}
            derived={p.name:digest(p) for p in (native,model)}
        binary=out/(name+'.vvp')
        result=subprocess.run(['C:/iverilog/bin/iverilog.exe',language,'-s','tb',*extra,'-o',str(binary),*map(str,sources)],cwd=out,env=env,capture_output=True,text=True)
        log=result.stdout+result.stderr
        if not result.returncode:
            result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=1800);log+=result.stdout+result.stderr
        (out/(name+'.log')).write_text(log,encoding='utf-8')
        unchanged=all(digest(ROOT/p)==h for p,h in hashes.items()) and all(digest(Path(p))==h for p,h in external.items()) and all(digest(out/p)==h for p,h in derived.items())
        passed=result.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
        print(name+': '+next((s for s in log.splitlines() if s.startswith('PASS ')),log[-2500:]),flush=True)
        return dict(test=name,passed=passed,inputs_unchanged=unchanged,seconds=round(time.monotonic()-start,2),
                    inputs_sha256=hashes,external_inputs_sha256=external,stimuli_sha256=stimuli,derived_sha256=derived,
                    log_sha256=digest(out/(name+'.log')))
    selected=a.only or JOBS
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,selected))
    report=out/'results.json';previous=json.loads(report.read_text()) if report.exists() and a.only else []
    report.write_text(json.dumps([r for r in previous if r['test'] not in selected]+results,indent=2)+'\n',encoding='utf-8')
    if not all(r['passed'] for r in results):raise SystemExit('Spotlight alignment verification failed')
if __name__=='__main__':main()
