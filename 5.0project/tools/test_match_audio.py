"""Prove the A-only predictive FIFO and SPI remain cycle-exact."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,subprocess
from prepare_match_audio import verify
ROOT=Path(__file__).resolve().parents[1];IV=Path('C:/iverilog/bin/iverilog.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 verify();ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--only',nargs='+');a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 def run(name):
  d=out/name;d.mkdir(exist_ok=True);params=[]
  if name in ('award_column','award_column_shared'):
   top='tb';params=['-Ptb.SHARED='+('1' if name.endswith('shared') else '0')];files=['tests/tb_match_award_column.v','tests/reference/match_single/award_fx_before_match.v','common/award_fx.v','common/award_sprite_rom.v']
  elif name=='spi_registered':
   top='tb_hmi_remote_spi';files=['tests/tb_match_audio_spi.v','common/photo_hmi_remote.v','common/photo_audio_link.v','common/photo_audio_spi_b_offload.v','common/photo_processing.v','common/match/photo_match_audio_spi.v','common/match/photo_match_audio_fifo.v']
  else:
   top='tb';params=['-Ptb.AW='+('3' if name=='fifo_8' else '11')];files=['tests/tb_match_audio_fifo.v','common/photo_audio_link.v','common/match/photo_match_audio_fifo.v']
  paths=[ROOT/f for f in files];hashes={f:sha(ROOT/f) for f in files};binary=d/'run.vvp'
  r=subprocess.run([str(IV),'-g2012','-DVICTORY_SIM',*params,'-s',top,'-o',str(binary),*map(str,paths)],capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:
   r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600);log+=r.stdout+r.stderr
  (d/'run.log').write_text(log);passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
  assert hashes=={f:sha(ROOT/f) for f in hashes};print(name+': '+log[-1800:],flush=True)
  return dict(test=name,passed=passed,inputs_sha256=hashes,log=str(d/'run.log'),log_sha256=sha(d/'run.log'))
 jobs=a.only or ['fifo_8','fifo_2048','spi_registered','award_column','award_column_shared']
 assert set(jobs)<={'fifo_8','fifo_2048','spi_registered','award_column','award_column_shared'}
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:records=list(pool.map(run,jobs))
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n');assert all(r['passed'] for r in records)
if __name__=='__main__':main()
