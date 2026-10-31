"""Exhaustive exact RGB565 channel packing and two-slot protocol, behavioural and vendor DSP."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 import os
 temp=Path("E:/Codex/Temp/saixian-resource-save-20261024");temp.mkdir(parents=True,exist_ok=True)
 os.environ.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
 model=vendor.read_text().split('`pragma protect begin_protected',1)[0]
 # Same static parameter mux adaptation used by test_fx11_water.py for Icarus.
 # Preserve the supplied vendor arithmetic and all register behaviour.
 begin=model.index('   always @(param_trig)');end=model.index('   end // always',begin)+len('   end // always')
 model=model[:begin]+model[begin:end].replace('always @(param_trig)','always @*').replace('assign ','')+model[end:]
 native=out/'vendor_mult18_functional.v';native.write_text(model,encoding='utf-8')
 files=[ROOT/'tests/fx11_water/tb_packed_surface.v',ROOT/'common/fluid/water_surface.v']
 records=[]
 for kind in ['packed_surface','packed_surface_native']:
  start=time.monotonic();is_native=kind.endswith('_native');current=files+([ROOT/'tests/fx11_water/glbl.v'] if is_native else [])
  inputs={p.relative_to(ROOT).as_posix():sha(p) for p in current+[Path(__file__)]};external={str(vendor):sha(vendor)} if is_native else {}
  stimuli={native.name:sha(native)} if is_native else {}
  binary=out/(kind+'.vvp');extra=['-DFX11_DSP_SIM','-s','glbl'] if is_native else []
  command=['C:/iverilog/bin/iverilog.exe','-g2012','-DWATER_SIM','-s','tb',*extra,'-o',str(binary),*map(str,current+([native] if is_native else []))]
  run=subprocess.run(command,cwd=out,capture_output=True,text=True);log=run.stdout+run.stderr
  if run.returncode==0:
   run=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=300);log+=run.stdout+run.stderr
  path=out/(kind+'.log');path.write_text(log,encoding='utf-8')
  unchanged=inputs=={p:sha(ROOT/p) for p in inputs} and external=={p:sha(Path(p)) for p in external} and stimuli=={p:sha(out/p) for p in stimuli}
  passed=run.returncode==0 and 'pair_cases=262144 green_cases=16384 two_pixel_transactions=4096' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
  record=dict(test=kind,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=inputs,external_inputs_sha256=external,stimuli_sha256=stimuli,inputs_unchanged=unchanged,log=str(path),log_sha256=sha(path));records.append(record)
  print(kind+': '+log.strip()[-600:],flush=True)
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in records):raise SystemExit(1)
if __name__=='__main__':main()
