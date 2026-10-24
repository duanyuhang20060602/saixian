"""Compare shared and separate production award caches across full mode transitions."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
from test_relief_bus import decode,savehex
ROOT=Path(__file__).resolve().parents[1]
FILES=['tests/tb_relief_shared_cache.v','common/photo_award_render.v','common/photo_relief_player.v','common/photo_relief_motion.v','common/photo_spotlight_player.v','common/award_fx.v','common/award_sprite_rom.v','common/photo_display_pipe.v']
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--asset',type=Path,required=True);ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);temp=out/'temp';temp.mkdir(exist_ok=True)
 env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 old=ROOT/'award_media/AWARD720.DLT'
 _,_,tail,_=decode(old);savehex(out/'legacy_tail.hex',tail)
 _,plate,tail,_=decode(a.asset);savehex(out/'relief_tail.hex',tail);savehex(out/'relief_base.hex',plate.view('<u2'),4)
 files=[ROOT/p for p in FILES];evidence=files+[Path(__file__),ROOT/'tools/test_relief_bus.py',old,a.asset]+[out/p for p in ['legacy_tail.hex','relief_tail.hex','relief_base.hex']]
 hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
 started=time.monotonic();binary=out/'shared.vvp'
 p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DRELIEF_SIM','-DWATER_SIM','-DERAM_SIM','-s','tb','-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  print('Compiled two real production renderers; starting full mode-transition differential',flush=True)
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=2400);log+=p.stdout+p.stderr
 path=out/'shared_cache.log';path.write_text(log,encoding='utf-8')
 unchanged=all(sha(ROOT/q if not Path(q).is_absolute() else Path(q))==h for q,h in hashes.items())
 passed=p.returncode==0 and 'PASS shared award cache:' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
 record=dict(test='shared_cache',passed=passed,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,inputs_unchanged=unchanged,log=str(path),log_sha256=sha(path),asset_sha256=sha(a.asset),scope='Two production renderers, independent caches versus a shared synchronous 512x32 cache. Six full 720p frames and old-new-old transitions, 50MHz memory/75MHz video, randomized grant waits, mixed four/sixty-four-word response bursts, pause/touch, same-cycle final RGB/menu/errors/frame indexes and identical memory requests.')
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit('Shared-cache differential failed')
if __name__=='__main__':main()
