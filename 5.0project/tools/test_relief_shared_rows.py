"""Check the legacy row write port against every field of the accepted raw donor."""
from pathlib import Path
import argparse,hashlib,json,os,re,struct,subprocess,time
from test_relief_bus import decode,savehex
from prepare_award_v5 import ACCEPTED
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 donor=ROOT/'tests/reference/accepted_v3/AWARD720.DLT';assert sha(donor)==ACCEPTED
 blob=donor.read_bytes();table=struct.unpack_from('<I',blob,260)[0];raw=[]
 for f in range(120):
  off,words,crc,seq=struct.unpack_from('<4I',blob,(table+4*f)*4);assert words==3600
  raw.extend(struct.unpack_from('<2720I',blob,off*4))
 old=ROOT/'award_media/AWARD720.DLT';_,_,tail,_=decode(old)
 savehex(out/'light_raw.hex',raw);savehex(out/'light_tail.hex',tail)
 files=[ROOT/p for p in ['tests/tb_award_v5_rows.v','common/photo_spotlight_player.v','common/photo_award_memory.v']]
 evidence=files+[donor,old,Path(__file__),ROOT/'tools/test_relief_bus.py',ROOT/'tools/prepare_award_v5.py',out/'light_raw.hex',out/'light_tail.hex']
 hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
 temp=out/'temp';temp.mkdir(exist_ok=True);env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp));started=time.monotonic()
 binary=out/'rows.vvp';p=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DWATER_SIM','-s','tb','-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
 if p.returncode==0:
  p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=1200);log+=p.stdout+p.stderr
 path=out/'shared_legacy_rows.log';path.write_text(log,encoding='utf-8');unchanged=all(sha(Path(k) if Path(k).is_absolute() else ROOT/k)==h for k,h in hashes.items())
 passed=p.returncode==0 and 'PASS lossless sparse row decode:' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
 record=dict(test='shared_legacy_rows',passed=passed,inputs_sha256=hashes,inputs_unchanged=unchanged,seconds=round(time.monotonic()-started,2),log=str(path),log_sha256=sha(path),scope='Production row decoder and arbiter versus pinned independent uncompressed donor, all 120 fields and 68 rows, both current/following cache banks, wrap, refresh/contention.')
 (out/'results.json').write_text(json.dumps([record],indent=2)+'\n',encoding='utf-8');print(log,flush=True)
 if not passed:raise SystemExit('Legacy row write regression failed')
if __name__=='__main__':main()
