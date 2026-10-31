"""Deterministic small noise parameter field; no photo/video data is stored."""
from pathlib import Path
import argparse,math,random
ROOT=Path(__file__).resolve().parents[1]
def files():
 rng=random.Random(20261025);values=[]
 for term in range(4):
  phases=[rng.random()*2*math.pi for _ in range(6)]
  for i in range(256):
   v=sum(math.sin(2*math.pi*i/256*2**j+phases[j])*.58**j for j in range(6))*54
   values.append(max(-128,min(127,round(v)))&511)
 hx=''.join(f'{v:03x}\n' for v in values)
 mif='DEPTH = 1024;\nWIDTH = 9;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n'+''.join(f'{i:03X} : {v:03X};\n' for i,v in enumerate(values))+'END;\n'
 return {'water_color_noise.hex':hx,'water_color_noise.mif':mif}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path);o=ap.parse_args()
 for name,data in files().items():
  if o.out:o.out.mkdir(parents=True,exist_ok=True);(o.out/name).write_text(data,encoding='ascii')
  else:assert (ROOT/'common/fluid'/name).read_text(encoding='ascii')==data
 print('PASS deterministic 1024x9 projected noise parameters')
if __name__=='__main__':main()
