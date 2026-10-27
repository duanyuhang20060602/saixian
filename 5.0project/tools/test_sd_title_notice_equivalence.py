"""Exhaust the entire notice panel against the frozen original renderer."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--iverilog',type=Path,required=True);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 files=[ROOT/n for n in ['tests/tb_sd_title_notice_equivalence.v','common/photo_award_render.v','tests/reference/sd_title/photo_award_notice.v']]
 inputs={str(p):sha(p) for p in files+[Path(__file__)]};start=time.monotonic();binary=out/'notice.vvp'
 r=subprocess.run([str(a.iverilog),'-g2012','-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:
  r=subprocess.run([str(a.iverilog.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=180);log+=r.stdout+r.stderr
 (out/'notice_equivalence.log').write_text(log)
 passed=r.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and all(sha(Path(p))==v for p,v in inputs.items())
 (out/'results.json').write_text(json.dumps(dict(cases=[dict(test='notice_equivalence',passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=inputs,log_sha256=sha(out/'notice_equivalence.log'))]),indent=2)+'\n')
 print(log[-2500:]);assert passed
if __name__=='__main__':main()
