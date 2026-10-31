"""Verify optimized key ticks, native packed font and actual34-clock mode mux."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,re,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
HDL=ROOT/'common/match'
IV=Path('C:/iverilog/bin/iverilog.exe')
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 def run(name):
  d=out/name;d.mkdir(exist_ok=True);defines=[];evidence=[]
  if name=='keys_tick':sources=[ROOT/'tests/tb_match_keys_tick.v',HDL/'photo_match_control.v']
  elif name=='legacy_keys':sources=[ROOT/'tests/tb_match_legacy_keys.v',HDL/'photo_match_manager.v',HDL/'photo_match_serial.v',HDL/'photo_match_control.v']
  elif name=='font_native':
   sources=[ROOT/'tests/tb_match_font_native.v',HDL/'photo_match_font.v',ROOT/'tests/ip_vendor_ram_adapter.v',VENDOR]
   mif=HDL/'photo_match_font.mif';words=[None]*2048
   for address,word in re.findall(r'(\d+)\s*:\s*([0-9A-Fa-f]+)\s*;',mif.read_text()):words[int(address)]=int(word,16)
   assert all(w is not None for w in words)
   (d/'font_from_mif.hex').write_text(''.join(f'{w:04x}\n' for w in words))
   (d/'ip_init_map.vh').write_text('localparam HEX_FILE="font_from_mif.hex";\n')
   original=ROOT/'tests/reference/match_single/match_font.hex';shutil.copy2(original,d/'original_font.hex')
   # Capture original header functions independently of the packed production ROM.
   generator=d/'strings.v';generator.write_text("module dump;reg[2:0] fs,fa,fb;reg[9:0] sa,sb;reg[8:0] sec;reg[1:0] dur;integer i,j,f;reg[6:0] c[0:511];\n__BT__include \"match_text.vh\"\ninitial begin for(i=0;i<512;i=i+1)c[i]=0;for(i=0;i<6;i=i+1)for(j=0;j<4;j=j+1)c[i*4+j]=team_char(i,j);for(i=0;i<5;i=i+1)for(j=0;j<8;j=j+1)c[32+i*8+j]=state_char(i,j);for(i=0;i<6;i=i+1)for(j=0;j<16;j=j+1)c[80+i*16+j]=message_char(i,j);for(i=0;i<8;i=i+1)for(j=0;j<32;j=j+1)c[192+i*32+j]=help_char(i,j);fs=0;fa=0;fb=1;sa=0;sb=0;sec=30;dur=0;for(j=0;j<13;j=j+1)c[448+j]=cell_glyph(j+2,1);for(j=0;j<4;j=j+1)c[464+j]=cell_glyph(j+16,7);fs=2;sec=10;for(j=0;j<4;j=j+1)c[468+j]=cell_glyph(j+16,16);f=$fopen(\"text_ids.hex\",\"w\");for(i=0;i<512;i=i+1)$fdisplay(f,\"%02x\",c[i]);$fclose(f);$finish;end endmodule\n".replace('__BT__',chr(96)))
   subprocess.run([str(IV),'-g2012','-I'+str(ROOT/'tests/reference/match_single'),'-s','dump','-o',str(d/'strings.vvp'),str(generator)],check=True,capture_output=True)
   subprocess.run([str(IV.with_name('vvp.exe')),str(d/'strings.vvp')],cwd=d,check=True,capture_output=True)
   evidence=[mif,original,ROOT/'tests/reference/match_single/match_text.vh',generator,d/'font_from_mif.hex',d/'text_ids.hex',d/'ip_init_map.vh']
  else:
   sources=[ROOT/'tests/tb_match_video.v',ROOT/'common/photo_raster_delay.v',HDL/'photo_match_video.v',HDL/'photo_match_render.v',HDL/'photo_match_numbers.v',HDL/'photo_match_font.v',HDL/'photo_match_text_query.v',HDL/'photo_match_columns.v'];defines=['MATCH_SIM']
   shutil.copy2(HDL/'photo_match_font.hex',d/'photo_match_font.hex');shutil.copy2(HDL/'photo_match_columns.hex',d/'photo_match_columns.hex');evidence=[HDL/'photo_match_font.hex',HDL/'photo_match_columns.hex']
  hashes={str(p):sha(p) for p in [Path(__file__),*sources,*evidence]};binary=d/'run.vvp'
  r=subprocess.run([str(IV),'-g2012',*['-D'+v for v in defines],'-I'+str(d),'-s','tb','-o',str(binary),*map(str,sources)],capture_output=True,text=True);log=r.stdout+r.stderr
  if r.returncode==0:
   r=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=d,capture_output=True,text=True,timeout=600);log+=r.stdout+r.stderr
  (d/'run.log').write_text(log);passed=r.returncode==0 and 'PASS' in log and 'FATAL' not in log
  assert hashes=={p:sha(Path(p)) for p in hashes},'Test inputs changed'
  print(name+': '+log[-1600:],flush=True)
  return dict(test=name,passed=passed,source_sha256=hashes,log=str(d/'run.log'),log_sha256=sha(d/'run.log'))
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:results=list(pool.map(run,['keys_tick','legacy_keys','font_native','video']))
 (out/'results.json').write_text(json.dumps(results,indent=2)+'\n');assert all(r['passed'] for r in results)
if __name__=='__main__':main()
