"""Exercise color-dodge arithmetic, the shared DSP and RGB neighborhood flush."""
from pathlib import Path
import argparse,hashlib,json,random,re,subprocess,os
from color_ripple_reference import lighting,fringe
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out;out.mkdir(parents=True,exist_ok=True)
 import sys
 sys.path.insert(0,str(ROOT/'tests/reference/fx11_water'))
 from effects_reference import lighting as legacy
 rng=random.Random(20261025);lines=[]
 for cm in range(2):
  for s in range(32):
   for h in range(8):
    for r in range(32):
     b=(r*17+s*7+h)%32;g=(r*3+s*11+h)%64
     pixel=(r<<11)|(g<<5)|b;w=(pixel<<16)|rng.randrange(65536)
     e=lighting(w,s) if cm else legacy(w,s,h)
     lines.append(f'{cm} {w:08x} {s} {h} {e:08x}')
 (out/'color_light_vectors.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
 inputs=[];expected=[]
 for row in range(12):
  pixels=[rng.randrange(65536) for _ in range(640)];amounts=[row if row<8 else rng.randrange(8) for _ in range(320)]
  inputs.extend(f'{(pixels[i*2]<<16)|pixels[i*2+1]:08x} {amounts[i]}' for i in range(320))
  v=fringe(pixels,amounts);expected.extend(f'{(v[i*2]<<16)|v[i*2+1]:08x}' for i in range(320))
 (out/'color_fringe_input.txt').write_text('\n'.join(inputs)+'\n');(out/'color_fringe_expected.txt').write_text('\n'.join(expected)+'\n')
 files=[ROOT/'tests/fx11_water/tb_color_surface.v',ROOT/'common/fluid/water_surface.v',ROOT/'common/fluid/water_priority_map.v',Path(__file__),ROOT/'tools/color_ripple_reference.py',ROOT/'tests/reference/fx11_water/effects_reference.py']
 records=[]
 for native in [False,True]:
  name='color_surface_native' if native else 'color_surface';binary=out/(name+'.vvp');extra=[];external=[]
  if native:
   vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
   model=vendor.read_text().split('`pragma protect begin_protected',1)[0]
   begin=model.index('   always @(param_trig)');end=model.index('   end // always',begin)+len('   end // always')
   model=model[:begin]+model[begin:end].replace('always @(param_trig)','always @*').replace('assign ','')+model[end:]
   native_model=out/'vendor_mult18_functional.v';native_model.write_text(model,encoding='utf-8')
   extra=['-DFX11_DSP_SIM','-s','glbl'];files_native=[native_model,ROOT/'tests/fx11_water/glbl.v'];external=[vendor]
  else:files_native=[]
  command=['C:/iverilog/bin/iverilog.exe','-g2005','-DWATER_SIM','-s','tb',*extra,'-o',str(binary),*map(str,files[:3]+files_native)]
  result=subprocess.run(command,cwd=ROOT,capture_output=True,text=True);log=result.stdout+result.stderr
  if result.returncode==0:
   result=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=180);log+=result.stdout+result.stderr
  p=out/(name+'.log');p.write_text(log,encoding='utf-8');print(name+': '+log[-1000:],flush=True)
  r=dict(test=name,passed=result.returncode==0 and 'PASS ' in log and not re.search(r'(?m)^(ERROR:|FATAL:)',log),inputs_sha256={p.relative_to(ROOT).as_posix():sha(p) for p in files+([ROOT/'tests/fx11_water/glbl.v'] if native else [])},external_inputs_sha256={str(p):sha(p) for p in external},stimuli_sha256={str(p):sha(p) for p in out.glob('*.txt')},log=str(p),log_sha256=sha(p))
  if native:r['stimuli_sha256'].update({str(p):sha(p) for p in files_native if not p.is_relative_to(ROOT)})
  records.append(r)
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n')
 assert all(r['passed'] for r in records)
if __name__=='__main__':main()
