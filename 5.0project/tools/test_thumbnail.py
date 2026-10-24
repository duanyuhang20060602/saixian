"""Thumbnail and affected-control regressions; all outputs stay on E:."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,subprocess,time

ROOT=Path(__file__).resolve().parents[1]
FRAME=[f'src/board_a/user_source/hdl_source/{p}' for p in
       ('frame_store.v','SD/frame_read_write.v','SD/frame_fifo_write.v','IP/afifo_32_16_256.v','IP/afifo_16_32_256.v')]
FLUID=['common/fluid/'+p for p in ('water_drop_small.v','water_reader.v','water_effect_map_base.v',
       'water_priority_map.v','water_surface.v','water_blend.v','water_cache.v','water_reconstruct.v')]
VENDOR=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
JOBS={
 'packing':('tb_thumbnail_packing',['tests/tb_thumbnail_packing.v','common/photo_thumbnail.v','tests/ip_vendor_ram_adapter.v',VENDOR],[]),
 'memory':('tb_thumbnail_memory',['tests/tb_thumbnail_memory.v','common/photo_thumbnail.v'],['THUMBNAIL_SIM']),
 'vendor':('tb_thumbnail_memory',['tests/tb_thumbnail_memory.v','common/photo_thumbnail.v','tests/ip_vendor_ram_adapter.v',VENDOR],[]),
 'overlay':('tb_thumbnail_overlay',['tests/tb_thumbnail_overlay.v','common/photo_thumbnail.v'],['THUMBNAIL_SIM']),
 'phase':('tb_thumbnail_phase',['tests/tb_thumbnail_phase.v','common/photo_thumbnail.v','common/photo_raster_delay.v'],['THUMBNAIL_SIM']),
 'blanking':('tb_thumbnail_blanking',['tests/tb_thumbnail_blanking.v','common/photo_thumbnail.v','common/photo_raster_delay.v'],['THUMBNAIL_SIM']),
 'bandwidth565':('tb_thumbnail_bandwidth',['tests/tb_thumbnail_bandwidth.v','common/photo_thumbnail.v','common/photo_raster_delay.v','common/photo_award_memory.v',*FRAME,*FLUID],['THUMBNAIL_SIM','WATER_SIM','THUMBNAIL_RGB565']),
 'live_bandwidth':('tb_thumbnail_bandwidth',['tests/tb_thumbnail_bandwidth.v','common/photo_thumbnail.v','common/photo_raster_delay.v','common/photo_award_memory.v',*FRAME,*FLUID],['THUMBNAIL_SIM','WATER_SIM','THUMBNAIL_RGB565','THUMBNAIL_DYNAMIC']),
 'control':('tb_thumbnail_control',['tests/tb_thumbnail_control.v','common/photo_cached_control_a.v','common/photo_uart.v'],[]),
 'touch':('tb_thumbnail_touch',['tests/tb_thumbnail_touch.v','common/top_photo_a.v','common/saixian_hmi_uart.v','common/photo_touchpad.v','common/photo_unified_settings_controller.v'],[]),
 'award_control':('tb',['tests/tb_award_v5_control.v','common/photo_cached_control_a.v','common/photo_control.v','common/photo_uart.v','common/photo_link.v'],[]),
 'award_width':('tb_v4_award_equivalence',['tests/tb_award_width.v','common/award_fx.v','common/award_sprite_rom.v','tests/reference/thumbnail/award_fx.v'],[]),
 'edge_eram':('tb_edge_equivalence',['tests/tb_edge_equivalence.v','common/fluid/water_edge.v','tests/reference/thumbnail/water_edge.v','tests/ip_vendor_ram_adapter.v',VENDOR],[]),
 'menu_geometry':('tb_menu_geometry',['tests/tb_menu_geometry.v','common/photo_settings_overlay.v','tests/reference/thumbnail/photo_settings_overlay.v','tests/touchscreen_menu_font.v'],['TOUCHSCREEN_SIM']),
}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--work',type=Path)
    ap.add_argument('--only',nargs='+',choices=list(JOBS));ap.add_argument('--reuse',action='store_true');args=ap.parse_args()
    out=(args.work or Path('E:/Codex/Work')/('thumbnail-tests-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S'))).resolve()
    assert out.drive.upper()=='E:',out
    out.mkdir(parents=True,exist_ok=True)
    Path('E:/Codex/Temp').mkdir(parents=True,exist_ok=True)
    os.environ.update(TEMP='E:/Codex/Temp',TMP='E:/Codex/Temp',TMPDIR='E:/Codex/Temp')
    iv=Path(os.environ.get('IVERILOG','C:/iverilog/bin/iverilog.exe'))
    result_file=out/'results.json'
    cache={r['test']:r for r in json.loads(result_file.read_text(encoding='utf-8'))} if result_file.exists() else {}
    for name in args.only or JOBS:
        top,sources,defines=JOBS[name];files=[(ROOT/Path(p)).resolve() for p in sources]
        extra=[];include_dir=out
        if name=='menu_geometry':
            for mif,converted,depth in [(ROOT/'common/photo_menu_font.mif',ROOT/'tests/touchscreen_results/menu_font.hex',2048),
                    (ROOT/'src/board_a/user_source/hdl_source/photo_menu_text_lookup.mif',ROOT/'src/board_a/user_source/hdl_source/photo_menu_text_lookup.hex',1024)]:
                values={}
                for first,last,single,value in re.findall(r'(?mi)^\s*(?:\[([0-9a-f]+)\.\.([0-9a-f]+)\]|([0-9a-f]+))\s*:\s*([0-9a-f]+)\s*;',mif.read_text()):
                    for address in range(int(first or single,16),int(last or single,16)+1):values[address]=int(value,16)
                assert [values[i] for i in range(depth)]==[int(v,16) for v in converted.read_text().split()]
                extra.extend([mif,converted])
        if name in ('vendor','edge_eram','packing'):
            # Keep each supplier RAM mapping immutable. A later shader test
            # must not overwrite the cache test's recorded include file.
            include_dir=out/(name+'_include');include_dir.mkdir(exist_ok=True)
            hex_file=''
            if name=='edge_eram':
                mif=ROOT/'src/board_a/user_source/hdl_source/IP/water_edge_weights.mif'
                values=re.findall(r'(?m)^([0-9A-F]+)\s*:\s*([0-9A-F]+);',mif.read_text())
                assert [int(a,16) for a,v in values]==list(range(128))
                converted=out/'edge_weights.hex';converted.write_text(''.join(v+'\n' for a,v in values))
                hex_file=converted.as_posix();extra.extend([mif,converted])
            include=include_dir/'ip_init_map.vh';include.write_text('localparam HEX_FILE="'+hex_file+'";\n',encoding='utf-8');extra.append(include)
        if name=='touch':
            text=(ROOT/'common/top_photo_a.v').read_text(encoding='utf-8')
            real={'saixian_hmi_uart','photo_touchpad','photo_pointer_overlay','photo_unified_settings_controller'}
            shells={}
            for m in re.finditer(r'^\s*([a-z]\w*_\w+)\s*(?:#\((.*?)\))?\s+(\w+)\s*\((.*?)\);',text,re.M|re.S):
                module,parameters,instance,ports=m.groups()
                if module in real or module=='module':continue
                names=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',ports)))
                params=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',parameters or '')))
                if module in shells:
                    names=list(dict.fromkeys(re.findall(r'input (\w+)',shells[module])+names))
                    params=list(dict.fromkeys(re.findall(r'parameter (\w+)',shells[module])+params))
                if names:shells[module]='module '+module+(' #('+','.join('parameter '+p+'=0' for p in params)+')' if params else '')+'('+','.join('input '+p for p in names)+'); endmodule'
            shell=out/'hardware_shells.v';shell.write_text('\n'.join(shells.values()),encoding='utf-8');files.append(shell)
        evidence=files+extra
        compile_files=list(files)
        hashes={p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
        old=cache.get(name,{})
        if args.reuse and old.get('passed') and old.get('inputs_sha256')==hashes and old.get('defines')==defines:
            print('REUSE verified inputs '+name,flush=True);continue
        binary=out/(name+'.vvp');start=time.monotonic()
        compiled=subprocess.run([str(iv),'-g2012','-I'+str(include_dir),*['-D'+d for d in defines],'-s',top,'-o',str(binary),*map(str,compile_files)],cwd=ROOT,capture_output=True,text=True)
        (out/(name+'_compile.log')).write_text(compiled.stdout+compiled.stderr,encoding='utf-8')
        compiled.check_returncode()
        with (out/(name+'.log')).open('w',encoding='utf-8') as log:
            run=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=1200 if name in ('bandwidth565','live_bandwidth') else 600)
        text=(out/(name+'.log')).read_text(encoding='utf-8')
        assert all(sha(p)==hashes[p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p)] for p in evidence),'Test inputs changed'
        passed=run.returncode==0 and 'PASS' in text and 'FATAL' not in text
        cache[name]={'test':name,'passed':passed,'seconds':round(time.monotonic()-start,2),'defines':defines,
                     'inputs_sha256':hashes,'log':str(out/(name+'.log')),'log_sha256':sha(out/(name+'.log'))}
        result_file.write_text(json.dumps(list(cache.values()),indent=2)+'\n',encoding='utf-8')
        print(text,flush=True)
        if not passed:raise SystemExit(1)
    print('Results: '+str(result_file),flush=True)

if __name__=='__main__':main()
