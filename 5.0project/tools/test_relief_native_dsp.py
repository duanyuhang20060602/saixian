"""Use the installed unmodified Anlogic multiplier model with production RTL."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, re, subprocess, time
from test_relief_bus import JOBS, vectors
ROOT=Path(__file__).resolve().parents[1]
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--asset',type=Path,required=True);ap.add_argument('--out',type=Path,required=True)
 ap.add_argument('--only',nargs='+',choices=('product_native','player_native','bus_native'));a=ap.parse_args()
 selected=a.only or ['product_native','player_native','bus_native']
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);temp=out/'temp';temp.mkdir(exist_ok=True)
 env=os.environ.copy();env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp),PYTHONDONTWRITEBYTECODE='1')
 if any(t!='product_native' for t in selected):vectors(out/'relief',a.asset,relief=True)
 def run(name):
  started=time.monotonic();folder=out/'relief';folder.mkdir(exist_ok=True)
  paths=(['tests/tb_relief_product_native.v','common/photo_relief_player.v','common/photo_relief_motion.v'] if name=='product_native' else JOBS[name.removesuffix('_native')])
  # TD ships a plaintext functional model followed by a protected appendix.
  # Icarus cannot parse the encrypted appendix; the model prefix is unchanged.
  model=folder/'eg_phy_mult18_functional.v'
  prefix=VENDOR.read_text().split('`pragma protect begin_protected',1)[0]
  model.write_text(prefix,encoding='utf-8')
  files=[ROOT/p for p in paths]+[ROOT/'tests/relief_native_glbl.v',model]
  evidence=files+[VENDOR,Path(__file__),ROOT/'tools/test_relief_bus.py']
  hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
  asset=sha(a.asset);binary=folder/(name+'.vvp')
  flags=['-DWATER_SIM','-DVICTORY_SIM','-DRELIEF_SIM','-DRELIEF_NATIVE_DSP','-DFX11_ROM_ROOT=""']
  c=['C:/iverilog/bin/iverilog.exe','-g2012',*flags,'-s','tb','-s','glbl','-o',str(binary),*map(str,files)]
  p=subprocess.run(c,cwd=folder,env=env,capture_output=True,text=True);log=p.stdout+p.stderr
  if p.returncode==0:
   p=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=folder,env=env,capture_output=True,text=True,timeout=900);log+=p.stdout+p.stderr
  path=out/(name+'.log');path.write_text(log,encoding='utf-8')
  unchanged=all(sha(q)==hashes[q.relative_to(ROOT).as_posix() if q.is_relative_to(ROOT) else str(q)] for q in evidence) and sha(a.asset)==asset
  passed=p.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
  print(name+': '+next((s for s in log.splitlines() if s.startswith('PASS ')),log[-2500:]),flush=True)
  return dict(test=name,passed=passed,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,inputs_unchanged=unchanged,asset_sha256=asset,log=str(path),log_sha256=sha(path),flags=flags)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:records=list(pool.map(run,selected))
 dest=out/'results.json';prior=json.loads(dest.read_text()) if dest.exists() else [];prior=[r for r in prior if r['test'] not in selected]
 dest.write_text(json.dumps(prior+records,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in records):raise SystemExit('Native DSP regression failed')
if __name__=='__main__':main()
