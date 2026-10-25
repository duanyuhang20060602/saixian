"""Compare independently addressed packed ROMs and both complete video paths."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,re,shutil,subprocess,time,sys
from prepare_menu_edge_rom import verify
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--only',nargs='+',choices=['rom','rom_native','pipeline_sim','pipeline_native','pipeline_pcm']);a=ap.parse_args()
 verify();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 selected=a.only or ['rom','rom_native','pipeline_sim','pipeline_native','pipeline_pcm']
 fixtures=[ROOT/'src/board_a/user_source/hdl_source'/n for n in ['photo_menu_text_lookup.hex','photo_menu_text_lookup.mif','photo_menu_edge_weights.hex','photo_menu_edge_weights.mif','IP/water_edge_weights.mif']]+[ROOT/'common/photo_menu_font.mif']
 def decode(path):
  values={}
  for lo,hi,s,v in re.findall(r'(?mi)^\s*(?:\[([0-9a-f]+)\.\.([0-9a-f]+)\]|([0-9a-f]+))\s*:\s*([0-9a-f]+);',path.read_text()):
   for i in range(int(lo or s,16),int(hi or s,16)+1):values[i]=int(v,16)
  assert set(values)==set(range(len(values)))
  return [values[i] for i in range(len(values))]
 def save(name,values,width=2):(out/name).write_text(''.join(f'{v:0{width}x}\n' for v in values),encoding='utf-8')
 save('edge_weights.hex',decode(fixtures[4]));save('menu_font.hex',decode(fixtures[5]),4)
 save('menu_map.hex',decode(fixtures[1]));save('menu_edge.hex',decode(fixtures[3]))
 for p in [fixtures[0],fixtures[2]]:
  q=out/p.relative_to(ROOT);q.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,q)
 (out/'ip_init_map.vh').write_text('localparam HEX_FILE=INIT_FILE=="photo_menu_font.mif" ? "menu_font.hex":INIT_FILE=="../src/board_a/user_source/hdl_source/photo_menu_text_lookup.mif" ? "menu_map.hex":INIT_FILE=="../src/board_a/user_source/hdl_source/photo_menu_edge_weights.mif" ? "menu_edge.hex":INIT_FILE=="../../src/board_a/user_source/hdl_source/IP/water_edge_weights.mif" ? "edge_weights.hex":"";\n',encoding='utf-8')
 def run(name):
  pipeline=name.startswith('pipeline');native=name in ['rom_native','pipeline_native','pipeline_pcm']
  files=[ROOT/('tests/tb_shared_menu_edge_'+('pipeline' if pipeline else 'rom')+'.v'),ROOT/'common/photo_settings_overlay.v',ROOT/'tests/reference/shared_rom/photo_settings_overlay.v']
  if pipeline:files += [ROOT/'common/fluid/water_edge.v',ROOT/'common/photo_menu_font.v',ROOT/'tests/reference/shared_rom/water_edge.v']
  if native or pipeline:files += [ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR]
  evidence=files+[Path(__file__),ROOT/'tools/prepare_menu_edge_rom.py',ROOT/'tests/reference/shared_rom/source.json',*fixtures,out/'ip_init_map.vh']
  hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};start=time.monotonic()
  flags=[] if native else ['-DTOUCHSCREEN_SIM']
  if name=='pipeline_pcm':flags+=['-P','tb.EXTERNAL=0']
  binary=out/(name+'.vvp');r=subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-I'+str(out),*flags,'-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:r=subprocess.run(['C:/iverilog/bin/vvp.exe',str(binary)],cwd=out,capture_output=True,text=True,timeout=900);log+=r.stdout+r.stderr
  lp=out/(name+'.log');lp.write_text(log,encoding='utf-8');passed=r.returncode==0 and 'PASS ' in log and not any(v in log for v in ['FATAL:','ERROR:']) and all(sha(p)==hashes[p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p)] for p in evidence)
  print(name+': '+log[-1800:],flush=True)
  return dict(test='shared_menu_edge_'+name,passed=passed,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,external_inputs_sha256={str(VENDOR):sha(VENDOR)} if native or pipeline else {},stimuli_sha256={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*.hex')}|{'ip_init_map.vh':sha(out/'ip_init_map.vh')},log=str(lp),log_sha256=sha(lp),flags=flags)
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:rows=list(pool.map(run,selected))
 dest=out/'results.json';old=json.loads(dest.read_text()) if dest.exists() else [];names={r['test'] for r in rows};dest.write_text(json.dumps([r for r in old if r['test'] not in names]+rows,indent=2)+'\n',encoding='utf-8')
 if not all(r['passed'] for r in rows):sys.exit(1)
if __name__=='__main__':main()
