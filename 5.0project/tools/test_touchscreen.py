from pathlib import Path
import subprocess,json,time,hashlib,os,re,sys
ROOT=Path(__file__).resolve().parents[1]
IV=Path(os.environ.get('IVERILOG',str(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe')))
OUT=ROOT/'tests/touchscreen_results';OUT.mkdir(exist_ok=True)
JOBS={
 'tb_spotlight_product':['common/photo_spotlight_player.v'],
 'tb_resolution_position':['common/audio_ui/saixian_osd_overlay.v'],
 'tb_next_button':['common/photo_touchpad.v'],
 'tb_touch_menu':['common/photo_settings_overlay.v','tests/touchscreen_menu_reference.v','tests/touchscreen_menu_font.v'],
 'tb_touch_top':['common/top_photo_a.v','common/saixian_hmi_uart.v','common/photo_touchpad.v','common/photo_unified_settings_controller.v'],
 'tb_pointer_settings':['common/photo_unified_settings_controller.v'],
 'tb_pointer_overlay':['common/photo_touchpad.v'],
 'tb_pointer_overlay_short':['common/photo_touchpad.v'],
 'tb_pointer_composed':['common/photo_touchpad.v','common/photo_raster_delay.v'],
 'tb_hmi':['common/saixian_hmi_uart.v'],
 'tb_v50_controls':['common/saixian_hmi_uart.v','common/photo_unified_settings_controller.v'],
 'tb_touch_uart':['common/saixian_hmi_uart.v'],
 'tb_touch_experiment':['common/saixian_hmi_uart.v','common/photo_touchpad.v'],
 'tb_touchpad':['common/photo_touchpad.v'],
}
def main():
 table=ROOT/'src/board_a/user_source/hdl_source/photo_menu_text_lookup'
 rom_words=[int(v,16) for v in table.with_suffix('.hex').read_text().split()]
 mif_words={int(a,16):int(v,16) for a,v in re.findall(r'(?mi)^([0-9a-f]+)\s*:\s*([0-9a-f]+);',table.with_suffix('.mif').read_text())}
 assert rom_words==[mif_words[i] for i in range(1024)] and max(rom_words)<128
 font=(ROOT/'common/photo_menu_font.mif').read_text(encoding='utf-8')
 values={}
 for first,last,single,value in re.findall(r'(?mi)^\s*(?:\[([0-9a-f]+)\.\.([0-9a-f]+)\]|([0-9a-f]+))\s*:\s*([0-9a-f]+)\s*;',font):
  for address in range(int(first or single,16),int(last or single,16)+1):values[address]=int(value,16)
 assert len(values)==2048
 (OUT/'menu_font.hex').write_text(''.join(f'{values[i]:04x}\n' for i in range(2048)),encoding='utf-8')
 prior={r['test']:r for r in json.loads((OUT/'results.json').read_text(encoding='utf-8'))} if '--reuse' in sys.argv and (OUT/'results.json').exists() else {}
 results=[]
 for name,deps in JOBS.items():
  files=['tests/'+name+'.v',*deps]
  if name=='tb_touch_top':
   # Use the actual production top and real touch modules. Omit unrelated
   # hardware blocks via explicit inert shells; clock/context are driven by TB.
   top=(ROOT/'common/top_photo_a.v').read_text(encoding='utf-8')
   real={'saixian_hmi_uart','photo_touchpad','photo_pointer_overlay','photo_unified_settings_controller'}
   shells={}
   for m in re.finditer(r'^\s*([a-z]\w*_\w+)\s*(?:#\((.*?)\))?\s+(\w+)\s*\((.*?)\);',top,re.M|re.S):
    module,parameters,instance,ports=m.groups()
    if module in real or module=='module':continue
    names=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',ports)))
    params=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',parameters or '')))
    if module in shells:
     names=list(dict.fromkeys(re.findall(r'input (\w+)',shells[module])+names))
     params=list(dict.fromkeys(re.findall(r'parameter (\w+)',shells[module])+params))
    if names:shells[module]='module '+module+(' #('+','.join('parameter '+p+'=0' for p in params)+')' if params else '')+'('+','.join('input '+p for p in names)+'); endmodule'
   shell=OUT/'top_hardware_shells.v';shell.write_text('\n'.join(shells.values()),encoding='utf-8');files.append(shell.relative_to(ROOT).as_posix())
  binary=OUT/(name+'.vvp')
  evidence=files+(['common/photo_menu_font.mif','tests/touchscreen_results/menu_font.hex','src/board_a/user_source/hdl_source/photo_menu_text_lookup.hex','src/board_a/user_source/hdl_source/photo_menu_text_lookup.mif'] if name=='tb_touch_menu' else [])
  hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in evidence}
  old=prior.get(name,{})
  if old.get('passed') and old.get('inputs_sha256')==hashes:
   results.append(old);print('REUSE verified inputs: '+name,flush=True);continue
  c=subprocess.run([str(IV),'-g2012',*(['-DTOUCHSCREEN_SIM'] if name=='tb_touch_menu' else ['-DWATER_SIM'] if name=='tb_spotlight_product' else []),'-s',name,'-o',str(binary),*files],cwd=ROOT,capture_output=True,text=True)
  (OUT/(name+'_compile.log')).write_text(c.stdout+c.stderr,encoding='utf-8');c.check_returncode()
  run=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600 if name=='tb_touch_menu' else 90)
  output=run.stdout+run.stderr;(OUT/(name+'.log')).write_text(output,encoding='utf-8');print(output,flush=True)
  passed=run.returncode==0 and 'PASS' in output and 'FATAL' not in output
  results.append(dict(test=name,passed=passed,inputs_sha256=hashes))
  (OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
  if not passed:raise SystemExit(1)
 (OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
