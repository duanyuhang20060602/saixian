"""Verify batched sampling, relocated click navigation and video coexistence."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,subprocess,time
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 temp=Path("E:/Codex/Temp/saixian-thumbnail-merge-20261025");temp.mkdir(parents=True,exist_ok=True)
 os.environ.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--iverilog',type=Path,required=True)
 ap.add_argument('--mode',choices=['unit','blanking','bandwidth','live_bandwidth','source_lock'],default='unit');ap.add_argument('--reuse',action='store_true');a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 prior={c['test']:c for c in json.loads((out/'results.json').read_text(encoding='utf-8-sig'))['cases']} if a.reuse and (out/'results.json').exists() else {}
 common=ROOT/'common';cases=[]
 vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
 (out/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n',encoding='ascii')
 dependencies=[Path(__file__),ROOT/'tests/tb_thumbnail_memory.v',ROOT/'tests/tb_thumbnail_blanking.v',ROOT/'tests/tb_thumbnail_bandwidth.v',ROOT/'tests/reference/thumbnail_button_before/photo_thumbnail.v']
 reference=ROOT/'tests/reference/thumbnail_button_before/photo_thumbnail.v'
 s=reference.read_text(encoding='utf-8-sig')
 for name in ('photo_thumbnail_memory','photo_thumbnail_cache','photo_thumbnail_overlay'):s=s.replace(name,name+'_before')
 before=out/'thumbnail_before.v';before.write_text(s)
 if a.mode=='source_lock':
  cases=[('source_lock',[ROOT/'tests/tb_thumbnail_source_lock.v',common/'photo_cached_control_a.v',common/'photo_uart.v'],[],'tb')]
 elif a.mode=='unit':
  fixture=(ROOT/'tests/tb_thumbnail_memory.v').read_text(encoding='utf-8-sig').replace('28224','40320')
  (out/'memory.v').write_text(fixture)
  cases=[('memory',[out/'memory.v',common/'photo_thumbnail.v'],['-DTHUMBNAIL_SIM'],'tb_thumbnail_memory'),
   ('vendor',[out/'memory.v',common/'photo_thumbnail.v',ROOT/'tests/ip_vendor_ram_adapter.v',vendor],['-I'+str(out)],'tb_thumbnail_memory'),
   ('overlay',[ROOT/'tests/tb_thumbnail_overlay.v',common/'photo_thumbnail.v'],['-DTHUMBNAIL_SIM'],'tb_thumbnail_overlay'),
   ('cancel',[ROOT/'tests/tb_thumbnail_early_cancel.v',common/'photo_thumbnail.v'],['-DTHUMBNAIL_SIM'],'tb_thumbnail_early_cancel'),
   ('pointer',[ROOT/'tests/tb_pointer_overlay.v',common/'photo_touchpad.v'],[],'tb_pointer_overlay'),
   ('arrow_removed',[ROOT/'tests/tb_thumbnail_arrow_removed.v',common/'photo_touchpad.v'],[],'tb'),
   ('new_phase',[ROOT/'tests/tb_thumbnail_button_phase.v',common/'photo_thumbnail.v',common/'photo_raster_delay.v'],['-DTHUMBNAIL_SIM'],'tb_thumbnail_phase')]
  # Only the UI/UART/pointer/settings modules are real in this wiring test;
  # physical PLLs, SDRAM and unrelated renderers use generated port shells.
  text=(common/'top_photo_a.v').read_text(encoding='utf-8-sig');real={'saixian_hmi_uart','photo_touchpad','photo_pointer_overlay','photo_unified_settings_controller'};shells={}
  for m in re.finditer(r'^\s*([a-z]\w*_\w+)\s*(?:#\((.*?)\))?\s+(\w+)\s*\((.*?)\);',text,re.M|re.S):
   module,parameters,instance,ports=m.groups()
   if module in real or module=='module':continue
   names=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',ports)));params=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',parameters or '')))
   if module in shells:
    names=list(dict.fromkeys(re.findall(r'input (\w+)',shells[module])+names));params=list(dict.fromkeys(re.findall(r'parameter (\w+)',shells[module])+params))
   if names:shells[module]='module '+module+(' #('+','.join('parameter '+p+'=0' for p in params)+')' if params else '')+'('+','.join('input '+p for p in names)+'); endmodule'
  shell=out/'hardware_shells.v';shell.write_text('\n'.join(shells.values()))
  cases.append(('touch',[ROOT/'tests/tb_thumbnail_button_touch.v',common/'top_photo_a.v',common/'saixian_hmi_uart.v',common/'photo_touchpad.v',common/'photo_unified_settings_controller.v',shell],[],'tb_thumbnail_touch'))
 elif a.mode=='blanking':
  for old in (True,False):
   fixture=(ROOT/'tests/tb_thumbnail_blanking.v').read_text(encoding='utf-8-sig')
   if old:
    for name in ('photo_thumbnail_memory','photo_thumbnail_overlay'):fixture=fixture.replace(name,name+'_before')
   fixture=fixture.replace('if(reads!=28224 || frames>10 || frames<7)', 'if(reads!='+('28224' if old else '40320')+' || frames>10 || frames<2)')
   fixture=fixture.replace('wire blank=valid && y>=720;',"wire blank=valid && y>=720 && !(y==749 && x>=1394);")
   # Count the display only after the complete-cache handshake as before;
   # owned bursts drain within the early blanking guard, before active video.
   fixture=fixture.replace('if(!blank && !(y==0 && x<64))', 'if(valid && y<720)')
   fixture=fixture.replace('28224 source words',('28224' if old else '40320')+' source words')
   p=out/('blank_before.v' if old else 'blank_after.v');p.write_text(fixture)
   cases.append(('blanking_before' if old else 'blanking_after',[p,before if old else common/'photo_thumbnail.v',common/'photo_raster_delay.v'],['-DTHUMBNAIL_SIM'],'tb_thumbnail_blanking'))
 else:
  fixture=(ROOT/'tests/tb_thumbnail_bandwidth.v').read_text(encoding='utf-8-sig').replace('28224','40320')
  fixture=fixture.replace('photo_thumbnail_overlay #(.Y(528),','photo_thumbnail_overlay #(.X(1096),.Y(315),')
  fixture=fixture.replace('x>=1088 && x<1248 && y>=528 && y<618','x>=1096 && x<1256 && y>=315 && y<405')
  fixture=fixture.replace('(raster_valid && y>=720)', '(raster_valid && y>=720 && !(y==749 && x>=1394))')
  p=out/'bandwidth.v';p.write_text(fixture)
  names=['common/photo_thumbnail.v','common/photo_award_memory.v','common/photo_raster_delay.v']
  names += ['src/board_a/user_source/hdl_source/'+f for f in ['frame_store.v','SD/frame_read_write.v','SD/frame_fifo_write.v','IP/afifo_32_16_256.v','IP/afifo_16_32_256.v']]
  names += ['common/fluid/'+f for f in ['water_drop_small.v','water_reader.v','water_effect_map_base.v','water_priority_map.v','water_surface.v','water_blend.v','water_cache.v','water_reconstruct.v']]
  vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
  (out/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n')
  # These effects are disabled in this RGB565 coexistence test. Existing
  # ROM assets remain available under a nonempty prefix for Icarus strings.
  import shutil
  for h in (common/'fluid').glob('*.hex'):shutil.copy2(h,out/h.name)
  flags=['-DTHUMBNAIL_SIM','-DWATER_SIM','-DTHUMBNAIL_RGB565','-DFX11_ROM_ROOT="./"','-I'+str(out)]
  if a.mode=='live_bandwidth':flags.append('-DTHUMBNAIL_DYNAMIC')
  cases=[(a.mode,[p,*[ROOT/f for f in names],ROOT/'tests/ip_vendor_ram_adapter.v',vendor],flags,'tb_thumbnail_bandwidth')]
 def run(case):
  name,files,flags,top=case;evidence=files+dependencies+[out/'ip_init_map.vh'];hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence};binary=out/(name+'.vvp');start=time.monotonic()
  old=prior.get(name,{})
  if old.get('passed') and old.get('inputs_sha256')==hashes and old.get('flags')==flags:
   print('REUSE verified identical inputs: '+name,flush=True)
   return {**old,'reused_verified_inputs':True}
  p=subprocess.run([str(a.iverilog),'-g2012',*flags,'-s',top,'-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=p.stdout+p.stderr
  if p.returncode==0:
   try:
    p=subprocess.run([str(a.iverilog.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=1200);log+=p.stdout+p.stderr
   except subprocess.TimeoutExpired:
    log+='\nTIMEOUT: no PASS claimed.\n';p=subprocess.CompletedProcess([],124)
  (out/(name+'.log')).write_text(log)
  passed=p.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and all(sha(Path(k) if Path(k).is_absolute() else ROOT/k)==v for k,v in hashes.items())
  record=dict(test=name,passed=passed,log=str(out/(name+'.log')),flags=flags,seconds=round(time.monotonic()-start,2),inputs_sha256=hashes,log_sha256=sha(out/(name+'.log')))
  match=re.search(r'cache across (\d+) frame boundaries',log)
  if match:record['frame_boundaries']=int(match[1])
  print(name+': '+next((s for s in log.splitlines() if s.startswith('PASS ')),log[-3500:]),flush=True)
  return record
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:records=list(pool.map(run,cases))
 (out/'results.json').write_text(json.dumps(dict(base='transfer-speed candidate based on 390690f',cases=records),indent=2)+'\n')
 if not all(r['passed'] for r in records):raise SystemExit(1)
if __name__=='__main__':main()
