"""Native short video taps and signed normal DSP checks."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time,sys
ROOT=Path(__file__).resolve().parents[1]
TD=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',required=True,type=Path);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 mult=TD/'sim_release/eg4/eg_phy_mult18.v';dram=TD/'sim_release/eg4/eg_logic_dram.v'
 mp=out/'vendor_mult18_functional.v';mp.write_text(mult.read_text().split('`pragma protect begin_protected',1)[0],encoding='utf-8')
 dp=out/'vendor_dram_plain.v';text=dram.read_text();dp.write_text(text[:text.index('endmodule')+len('endmodule')]+'\n',encoding='utf-8')
 jobs=[('video_taps',['tests/tb_rebalance_video_taps.v','common/photo_relief_decode_cache.v','common/photo_display_pipe.v'],['-DERAM_SIM','-DRELIEF_SIM'],[],'-g2012'),
       ('video_taps_native',['tests/tb_rebalance_video_taps.v','common/photo_relief_decode_cache.v','common/photo_display_pipe.v'],['-DERAM_SIM'],[dp],'-g2005'),
       ('wall_product_native',['tests/tb_rebalance_wall_product.v','common/photo_relief_player.v','tests/relief_native_glbl.v'],['-DRELIEF_SIM','-DRELIEF_NATIVE_DSP','-s','glbl'],[mp],'-g2012')]
 records=[]
 for name,names,flags,models,lang in jobs:
  files=[ROOT/p for p in names]+models;evidence=files+[Path(__file__),mult if models==[mp] else dram]
  h={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};start=time.monotonic();binary=out/(name+'.vvp')
  r=subprocess.run(['C:/iverilog/bin/iverilog.exe',lang,*flags,'-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=300);log+=r.stdout+r.stderr
  lp=out/(name+'.log');lp.write_text(log,encoding='utf-8');passed=r.returncode==0 and 'PASS ' in log and 'FATAL:' not in log and 'ERROR:' not in log
  records.append(dict(test=name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=h,log=str(lp),log_sha256=sha(lp),stimuli_sha256={p.name:sha(p) for p in models},flags=flags))
  print(name+': '+log[-1800:],flush=True);(out/'results.json').write_text(json.dumps(records,indent=2)+'\n')
  if not passed:sys.exit(1)
if __name__=='__main__':main()
