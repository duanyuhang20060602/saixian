"""Exercise the native RAM ports with Anlogic's supplied memory model."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);a=p.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True);records=[]
 spec=importlib.util.spec_from_file_location('rank_pipeline',ROOT/'tools/test_rank_metadata_pipeline.py');pipeline=importlib.util.module_from_spec(spec);spec.loader.exec_module(pipeline)
 for name in ['parser','pixels','pipeline']:
  directory=out/name;directory.mkdir(exist_ok=True);assets=[]
  for stem in ['photo_rank_header','photo_rank_glyphs','photo_rank_columns']:
   mif=ROOT/'common'/f'{stem}.mif';text=mif.read_text();depth=int(re.search(r'DEPTH=(\d+)',text)[1]);words=[None]*depth
   for address,value in re.findall(r'(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;',text):words[int(address)]=int(value,16)
   assert all(w is not None for w in words)
   (directory/f'{stem}.hex').write_text(''.join(f'{w:04x}\n' for w in words));assets += [mif,directory/f'{stem}.hex']
  init=directory/'ip_init_map.vh';init.write_text('localparam HEX_FILE='+''.join(f'INIT_FILE=="{stem}.mif" ? "{stem}.hex":' for stem in ['photo_rank_header','photo_rank_glyphs','photo_rank_columns'])+'"";\n')
  if name=='parser':bench=ROOT/'tests/tb_complete_hmi_parser.v';source=ROOT/'common/match/photo_serial_text_runtime.v'
  elif name=='pixels':bench=ROOT/'tests/tb_complete_hmi_rank_pixels.v';source=ROOT/'common/saixian_battle_result_fx_pipelined.v'
  else:bench=directory/'bench.v';bench.write_text(pipeline.BENCH,encoding='ascii');source=ROOT/'common/saixian_battle_result_fx_pipelined.v'
  files=[bench,source,ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR];evidence=[Path(__file__),ROOT/'tools/test_rank_metadata_pipeline.py',*files,init,*assets]
  hashes={str(path):sha(path) for path in evidence};binary=directory/'run.vvp';iv=Path('C:/iverilog/bin/iverilog.exe')
  r=subprocess.run([str(iv),'-g2012','-I'+str(directory),'-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=directory,capture_output=True,text=True,timeout=120);log+=r.stdout+r.stderr
  (directory/'run.log').write_text(log);passed=r.returncode==0 and 'PASS ' in log and 'FATAL' not in log
  records.append(dict(test='native_rank_'+name,passed=passed,inputs_sha256=hashes,log=str(directory/'run.log'),log_sha256=sha(directory/'run.log')));print(name+': '+log[-2200:],flush=True)
 (out/'results.json').write_text(json.dumps(records,indent=2)+'\n');assert all(r['passed'] for r in records)
if __name__=='__main__':main()
