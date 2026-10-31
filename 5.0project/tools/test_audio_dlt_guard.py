"""Prove the sector guard's cycle-equivalence and accepted material decoding."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,struct,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();assert out.drive.upper()=='E:';out.mkdir(parents=True,exist_ok=True)
 env=os.environ.copy();temp=Path('E:/Codex/Temp/audio-dlt-guard');temp.mkdir(parents=True,exist_ok=True);env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 reference=ROOT/'tests/reference/photo_dlt_reader_f6.v';old=reference.read_text().replace('module photo_dlt_reader #','module reference_photo_dlt_reader #');ref=out/'reference_reader.v';ref.write_text(old,encoding='utf-8')
 package=ROOT/'award_media/AWARD720.DLT';raw=package.read_bytes();words=struct.unpack('<'+'I'*(len(raw)//4),raw)
 (out/'award_file.hex').write_text(''.join(f'{v:08x}\n' for v in words),encoding='ascii')
 expected=ROOT/'tests/vectors/award_v5/award_expected.hex';(out/'award_expected.hex').write_bytes(expected.read_bytes())
 def run(name):
  start=time.monotonic();bench=ROOT/('tests/tb_dlt_guard.v' if name=='guard' else 'tests/tb_award_v5_reader.v')
  files=[bench,ROOT/'tests/dlt_guard_equivalence.v',ROOT/'common/photo_sd/photo_dlt_reader.v',ROOT/'common/photo_sd/photo_dlt_header.v',ROOT/'common/photo_color_format.v',ref]
  evidence=[reference,package,expected,Path(__file__)];hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in files+evidence}
  binary=out/(name+'.vvp');c=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-s','tb','-s','equivalence','-o',str(binary),*map(str,files)],cwd=out,env=env,capture_output=True,text=True);log=c.stdout+c.stderr
  if c.returncode==0:
   c=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=900);log+=c.stdout+c.stderr
  path=out/(name+'.log');path.write_text(log,encoding='utf-8');passed=c.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log)
  for p,h in hashes.items():assert sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h
  print(name+': '+log[-2000:],flush=True)
  return {'test':name,'passed':passed,'seconds':round(time.monotonic()-start,2),'inputs_sha256':hashes,'log':str(path),'log_sha256':sha(path),'stimuli_sha256':{str(out/p):sha(out/p) for p in ['award_file.hex','award_expected.hex']}}
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:records=list(pool.map(run,['guard','reader']))
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in records):raise SystemExit(1)
if __name__=='__main__':main()
