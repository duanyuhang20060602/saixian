"""Focused regressions for page cues, UART sharing and configurable autoplay."""
from pathlib import Path
import hashlib, json, os, subprocess, sys

ROOT=Path(__file__).resolve().parents[1]
IV=Path(os.environ.get('IVERILOG', str(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe')))
OUT=ROOT/'tests/fx_audio_results'
AUDIO=['common/photo_audio_link.v','common/photo_audio_features.v','common/audio_ui/saixian_audio_repair.v','common/audio_ui/photo_audio_cue_samples.v']
JOBS={
 'tb_fx_dlt_bounds':['common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v'],
 'tb_fx_dlt':['common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v','common/photo_color_format.v'],
 'tb_fx_history':['common/audio_ui/saixian_audio_repair.v','tests/ip_vendor_ram_adapter.v'],
 'tb_fx_legacy_cues':['common/audio_ui/photo_audio_cue_samples.v'],
 'tb_fx_transition':AUDIO+['common/saixian_transition.v'],
 'tb_fx_protocol':['common/photo_audio_link.v'],
 'tb_fx_styles':['common/audio_ui/photo_audio_cue_samples.v'],
 'tb_fx_start':AUDIO,
 'tb_fx_scale':AUDIO,
 'tb_fx_audio':AUDIO,
 'tb_page_uart':['common/photo_uart.v','tests/page_uart_reference.v'],
 'tb_interval':['common/photo_auto_advance.v','common/photo_unified_settings_controller.v'],
 'tb_auto_compat':['common/photo_auto_advance.v','tests/page_auto_reference.v'],
 'tb_interval_menu':['common/photo_settings_overlay.v','tests/touchscreen_menu_font.v'],
 'tb_page_detector':AUDIO,
 'tb_no_resolution':['common/audio_ui/saixian_osd_overlay.v'],
 'tb_page_mix':AUDIO,
 'tb_page_audio':AUDIO,
 'tb_award_v5_audio':AUDIO,
}

def main():
    OUT.mkdir(exist_ok=True)
    prior={r['test']:r for r in json.loads((OUT/'results.json').read_text(encoding='utf-8'))} if '--reuse' in sys.argv and (OUT/'results.json').exists() else {}
    results=[];cache=dict(prior)
    for name, deps in JOBS.items():
        files=['tests/'+name+'.v', *deps]
        if name in ('tb_fx_dlt','tb_fx_dlt_bounds'):
            source=ROOT/'award_media/AWARD720.DLT'
            import struct
            data=source.read_bytes()
            (OUT/'award_file.hex').write_text('\n'.join(f'{w[0]:08x}' for w in struct.iter_unpack('<I',data))+'\n',encoding='utf-8')
        if name=='tb_fx_history':
            (OUT/'ip_init_map.vh').write_text('localparam HEX_FILE="";\n',encoding='utf-8')
            files+=['C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v','tests/fx_audio_results/ip_init_map.vh']
        evidence=files+(['common/photo_menu_font.mif','tests/touchscreen_results/menu_font.hex','src/board_a/user_source/hdl_source/photo_menu_text_lookup.hex','src/board_a/user_source/hdl_source/photo_menu_text_lookup.mif'] if name=='tb_interval_menu' else [])
        if name in ('tb_fx_dlt','tb_fx_dlt_bounds'):evidence+=['award_media/AWARD720.DLT','tests/vectors/award_v5/award_expected.hex','tests/fx_audio_results/award_file.hex']
        hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in evidence}
        old=prior.get(name,{})
        if old.get('passed') and old.get('inputs_sha256')==hashes:
            results.append(old);print('REUSE verified inputs: '+name,flush=True);continue
        binary=OUT/(name+'.vvp')
        build=subprocess.run([str(IV),'-g2012',*(['-I'+str(OUT)] if name=='tb_fx_history' else ['-DVICTORY_SIM']),'-DTOUCHSCREEN_SIM','-s',name,'-o',str(binary),*[p for p in files if not p.endswith('.vh')]],cwd=ROOT,capture_output=True,text=True)
        (OUT/(name+'_compile.log')).write_text(build.stdout+build.stderr,encoding='utf-8')
        build.check_returncode()
        run=subprocess.run([str(IV.with_name('vvp.exe')),str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=1200 if name=='tb_fx_dlt' else 600)
        output=run.stdout+run.stderr
        (OUT/(name+'.log')).write_text(output,encoding='utf-8')
        print(output,flush=True)
        passed=run.returncode==0 and 'PASS' in output and 'FATAL' not in output
        assert hashes=={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in evidence}, 'Inputs changed during simulation'
        record=dict(test=name,passed=passed,inputs_sha256=hashes)
        results.append(record);cache[name]=record
        (OUT/'results.json').write_text(json.dumps(list(cache.values()),indent=2)+'\n',encoding='utf-8')
        if not passed:raise SystemExit(1)
    (OUT/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
