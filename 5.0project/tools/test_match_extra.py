"""Native9K column mapping and simultaneous serial/physical controls."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1];IV=Path('C:/iverilog/bin/iverilog.exe');VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 def run(name):
  d=out/name;d.mkdir(exist_ok=True);evidence=[]
  if name=='priority':files=[ROOT/'tests/tb_match_priority.v',ROOT/'common/match/photo_match_control.v']
  else:
   files=[ROOT/'tests/tb_match_columns_native.v',ROOT/'common/match/photo_match_columns.v',ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR]
   mif=ROOT/'common/match/photo_match_columns.mif';words=[None]*1024
   for address,value in re.findall(r'(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;',mif.read_text()):words[int(address)]=int(value,16)
   assert all(v is not None and v<512 for v in words)
   (d/'columns_from_mif.hex').write_text(''.join(f'{v:03x}\n' for v in words))
   (d/'ip_init_map.vh').write_text('localparam HEX_FILE="columns_from_mif.hex";\n');evidence=[mif,d/'columns_from_mif.hex',d/'ip_init_map.vh']
  hashes={str(p):sha(p) for p in [*files,*evidence]};binary=d/'run.vvp'
  r=subprocess.run([str(IV),'-g2012','-I'+str(d),'-s','tb','-o',str(binary),*map(str,files)],capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:
   r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=d,capture_output=True,text=True,timeout=120);log+=r.stdout+r.stderr
  (d/'run.log').write_text(log);passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
  assert hashes=={p:sha(Path(p)) for p in hashes};print(name+': '+log[-1800:],flush=True)
  return dict(test=name,passed=passed,source_sha256=hashes,log=str(d/'run.log'),log_sha256=sha(d/'run.log'))
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(run,['priority','columns_native']))
 (out/'results.json').write_text(json.dumps(results,indent=2)+'\n');assert all(r['passed'] for r in results)
if __name__=='__main__':main()
