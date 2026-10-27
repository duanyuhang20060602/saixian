"""Validate eleven effects and sparse water without generating documentation/packages."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,os,re,shutil,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests/reference/fx11_water'))
from fx11_vectors import generate
GEOMETRY=['water_drop_small.v','water_reader.v','water_effect_map_base.v','water_priority_map.v',
          'water_surface.v','water_blend.v','water_cache.v','water_reconstruct.v']
SUITE={'effects':['water_effect_map_base.v','water_priority_map.v','water_surface.v'],
       'math':['water_drop_small.v'],'compact':['water_cache.v','water_drop_small.v'],
       'cache':['water_cache.v'],'scene':['water_scene.v'],'transition':['../saixian_transition.v'],
       'controls':['../saixian_hmi_uart.v','../photo_unified_settings_controller.v'],
       'boot':['../photo_boot_screen.v','../../tests/reference/fx11_water/photo_boot_screen.v'],
       'notice':['../photo_award_render.v','../../tests/reference/fx11_water/photo_award_notice.v'],
       'visual_plot':['../audio_ui/saixian_osd_overlay.v','../../tests/reference/fx11_water/saixian_osd_overlay.v'],
       'context':['../photo_cached_control_a.v','../photo_uart.v','../../tests/reference/fx11_water/photo_cached_control_a.v'],
       'protocol':['../photo_cached_control_a.v','../photo_uart.v','../../tests/reference/fx11_water/photo_cached_control_a.v'],
       'legacy':GEOMETRY+['../../src/board_a/user_source/hdl_source/SD/'+f for f in ['frame_read_write.v','frame_fifo_read.v','frame_fifo_write.v']]+
                ['../../src/board_a/user_source/hdl_source/IP/'+f for f in ['afifo_32_16_256.v','afifo_16_32_256.v']]+['../../tests/reference/fx11_water/water_expand.v'],
       'reader':GEOMETRY,'fx_reader':GEOMETRY}
for name,mode in [('water',6),('dwell',0),('native',7),('metal',5),('tunnel',9)]:
    SUITE['bandwidth_'+name]=GEOMETRY
for name in ['water','dwell','native']:SUITE['scanout_'+name]=GEOMETRY
SUITE['dsp_math']=SUITE['math']
SUITE['dsp_effects']=SUITE['effects']
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,default=Path('E:/Codex/Work/cooperate-fx11-water-tests-20261018'))
    ap.add_argument('--only',nargs='+',choices=SUITE);ap.add_argument('--jobs',type=int,default=3);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    env=os.environ.copy();temp=Path(env.get('SAIXIAN_TEMP_ROOT',str(ROOT.parent/'temp')))/'cooperate-fx11';temp.mkdir(parents=True,exist_ok=True)
    env.update(TEMP=str(temp),TMP=str(temp),TMPDIR=str(temp))
    for p in (ROOT/'common/fluid').glob('*.hex'):shutil.copy2(p,out/p.name)
    selected=args.only or list(SUITE)
    if not all((out/f).exists() for f in ['math_vectors.txt','effects_vectors.txt','reader_vectors.txt','fx_reader_vectors.txt','frame_checksums.hex']):
        print('Generating independent integer reference vectors...',flush=True);generate(out)
    # The simulated ROM and the explicitly placed FPGA macro use the same
    # coefficients, including the reciprocal's reconstructed seventeenth bit.
    for name in ['water_inverse16','water_fx_recip']:
        original='water_inverse' if name=='water_inverse16' else name
        words=[int(v,16) for v in (ROOT/'common/fluid'/(original+'.hex')).read_text().split()]
        stored={int(a,16):int(v,16) for a,v in re.findall(r'(?mi)^([0-9A-F]+)\s*:\s*([0-9A-F]+);',
                (ROOT/'common/fluid'/(name+'.mif')).read_text())}
        assert len(stored)==len(words) and all(stored[i]==(v&65535) for i,v in enumerate(words))
        if name=='water_inverse16':assert [i for i,v in enumerate(words) if v>=65536]==[1]
    iv=Path(env.get('IVERILOG',str(ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe')));vvp=iv.with_name('vvp.exe')
    vendor=Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/eg4/eg_phy_mult18.v')
    native_model=out/'vendor_mult18_functional.v'
    # The vendor supplies a complete plaintext functional module followed by
    # protected library material. Icarus uses that supplied functional module.
    model=vendor.read_text().split('`pragma protect begin_protected',1)[0]
    # Icarus does not continuously reevaluate procedural assign statements.
    # Translate only the complete static parameter-mux block to equivalent
    # combinational procedural assignments; keep vendor arithmetic/registers.
    mux_begin=model.index('   always @(param_trig)')
    mux_end=model.index('   end // always',mux_begin)+len('   end // always')
    mux=model[mux_begin:mux_end].replace('always @(param_trig)','always @*').replace('assign ','')
    model=model[:mux_begin]+mux+model[mux_end:]
    native_model.write_text(model,encoding='utf-8')
    dependencies=[Path(__file__),ROOT/'tools/fx11_vectors.py',ROOT/'tools/color_ripple_reference.py',*list((ROOT/'tests/reference/fx11_water').glob('*.py')),
                  *list((ROOT/'common/fluid').glob('*.hex')),*list((ROOT/'common/fluid').glob('*.mif'))]
    def run(name):
        started=time.monotonic();scan=name.startswith('scanout_');band=name.startswith('bandwidth_') or scan
        bench='cooperate_scanout' if scan else 'bandwidth' if band else name.removeprefix('dsp_')
        files=[ROOT/'tests/fx11_water'/('tb_'+bench+'.v'),*[(ROOT/'common/fluid'/f).resolve() for f in SUITE[name]]]
        extra=[]
        if name in ('reader','fx_reader') or band:files.append(ROOT/'tests/fx11_water/sdram_contract.v')
        if band:
            mode={'water':6,'dwell':0,'native':7,'metal':5,'tunnel':9}[name.split('_',1)[1]]
            extra=['-P','tb.TEST_MODE='+str(mode)]
            files.extend([ROOT/'tests/reference/fx11_water/water_expand.v',ROOT/'src/board_a/user_source/hdl_source/IP/afifo_32_16_256.v'])
            if scan:files.extend([ROOT/'src/board_a/user_source/hdl_source/frame_pixels.v',
                                  ROOT/'src/board_a/user_source/hdl_source/SD/frame_fifo_write.v'])
        external=[];native_files=[]
        if name.startswith('dsp_'):
            external=[vendor];native_files=[native_model]
            extra+=['-DFX11_DSP_SIM','-s','glbl']
            files.append(ROOT/'tests/fx11_water/glbl.v')
        external_hashes={str(p):digest(p) for p in external}
        hashes={p.relative_to(ROOT).as_posix():digest(p) for p in sorted(set(files+dependencies))}
        stimuli={p.name:digest(p) for p in sorted(out.glob('*vectors.txt'))}
        stimuli['frame_checksums.hex']=digest(out/'frame_checksums.hex')
        if native_files:stimuli[native_model.name]=digest(native_model)
        binary=out/(name+'.vvp')
        language='-g2012' if name in ('context','legacy','protocol') else '-g2005'
        if name=='legacy':extra+=['-DREFRESH_STRESS']
        command=[str(iv),language,'-DWATER_SIM','-DFX11_ROM_ROOT="'+out.as_posix()+'/"','-s','tb',*extra,'-o',str(binary),*map(str,files+native_files)]
        result=subprocess.run(command,cwd=out,env=env,capture_output=True,text=True)
        log=result.stdout+result.stderr
        if result.returncode==0:
            result=subprocess.run([str(vvp),str(binary)],cwd=out,env=env,capture_output=True,text=True,timeout=900)
            log+=result.stdout+result.stderr
        (out/(name+'.log')).write_text(log,encoding='utf-8')
        unchanged=(hashes=={p:digest(ROOT/p) for p in hashes} and stimuli=={p:digest(out/p) for p in stimuli}
                   and external_hashes=={p:digest(Path(p)) for p in external_hashes})
        passed=result.returncode==0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)',log) and unchanged
        print(name+': '+next((line for line in log.splitlines() if line.startswith('PASS ')),log.strip()),flush=True)
        return dict(test=name,passed=passed,seconds=round(time.monotonic()-started,2),inputs_sha256=hashes,
                    external_inputs_sha256=external_hashes,stimuli_sha256=stimuli,inputs_unchanged=unchanged,log_sha256=digest(out/(name+'.log')))
    report=out/'results.json'
    results=json.loads(report.read_text()) if args.only and report.exists() else []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for result in pool.map(run,selected):
            results=[r for r in results if r['test']!=result['test']]+[result]
            report.write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
    if not all(r['passed'] for r in results):raise SystemExit(1)
    print('PASS '+str(len(results))+' effect/water regressions',flush=True)
if __name__=='__main__':main()
