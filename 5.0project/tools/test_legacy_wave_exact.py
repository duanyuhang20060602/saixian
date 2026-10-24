"""Exhaustive direct wave lookup proof and complete 720p legacy award equivalence."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 reference=ROOT/'tests/reference/legacy_wave_before/award_fx.v';metadata=ROOT/'tests/reference/legacy_wave_before/source.json'
 original=reference.read_text().replace('module original_award_fx #','module award_fx #',1)
 assert hashlib.sha256(original.encode()).hexdigest()==json.loads(metadata.read_text())['original_normalized_sha256'],'Frozen original reference changed'
 files=[ROOT/'tests/tb_legacy_wave_exact.v',ROOT/'common/award_fx.v',reference,ROOT/'common/award_sprite_rom.v']
 evidence=files+[Path(__file__),metadata];hashes={p.relative_to(ROOT).as_posix():sha(p) for p in evidence}
 temp=out/'temp';temp.mkdir(exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 started=time.monotonic();binary=out/'wave_exact.vvp'
 p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=600);log+=p.stdout+p.stderr
 path=out/'legacy_wave_exact.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(ROOT/q)==h for q,h in hashes.items())
 passed=p.returncode==0 and log.count('PASS ')==2 and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
 record=dict(test='legacy_wave_exact',passed=passed,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,inputs_unchanged=unchanged,log=str(path),log_sha256=sha(path),scope='512-phase exhaustive function comparison; same-cycle complete 1280x720 award_fx output differential against frozen original production source renamed only; shared real sprite ROM; five-clock bypass identity checked.')
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit('Legacy wave exact proof failed')
if __name__=='__main__':main()
