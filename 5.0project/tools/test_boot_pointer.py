"""Regress complete-scan startup gates and per-transition pointer origin."""
from pathlib import Path
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
 out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
 iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe'
 results=[]
 for name,files in [('boot',['tests/tb_complete_scan_boot.v','common/photo_boot_screen.v']),('origin',['tests/tb_pointer_transition_origin.v','common/fluid/water_scene.v']),('empty_text',['tests/tb_empty_sd_text.v','common/audio_ui/saixian_osd_overlay.v']),('catalog',['tests/tb_boot_catalog_status.v','tests/title_font_ram_model.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/audio_ui/saixian_font_rom.v'])]:
  paths=[ROOT/f for f in files];binary=out/(name+'.vvp')
  r=subprocess.run([str(iv),'-g2005','-s','tb','-o',str(binary),*map(str,paths)],capture_output=True,text=True,cwd=ROOT);log=r.stdout+r.stderr
  if r.returncode==0:
   r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],capture_output=True,text=True,cwd=ROOT,timeout=600);log+=r.stdout+r.stderr
  (out/(name+'.log')).write_text(log,encoding='utf-8');print(log,flush=True)
  results.append({'test':name,'passed':r.returncode==0 and 'PASS ' in log and 'FATAL' not in log,'inputs_sha256':{f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in files}})
 (out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 assert all(r['passed'] for r in results)
if __name__=='__main__':main()
