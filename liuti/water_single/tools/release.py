from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil,struct,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]

def hashes():
    files=[ROOT/'project'/'WATER_SINGLE.al']
    root=ET.parse(files[0]).getroot()
    files += [(ROOT/'project'/f.get('Path')).resolve() for f in root.findall('./Source_Files/*/File')]
    files += list((ROOT/'rtl').glob('water_*.hex'))+[ROOT/'project'/'water_global_def.v',ROOT/'project'/'build.tcl']
    return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--begin',action='store_true');args=ap.parse_args()
    state=ROOT/'validation'/'build_inputs.json'
    if args.begin:
        state.write_text(json.dumps(dict(start=datetime.datetime.now().timestamp(),hashes=hashes()),indent=2));return
    inputs=json.loads(state.read_text());assert inputs['hashes']==hashes(),'Build inputs changed; rebuild required'
    for rom in (ROOT/'rtl').glob('water_*.hex'):
        for directory in [ROOT/'project',ROOT/'tests',ROOT.parent]:
            assert (directory/rom.name).read_bytes()==rom.read_bytes(),f'ROM alias differs: {directory/rom.name}'
    header=(ROOT/'project'/'water_global_def.v').read_bytes()
    assert header==(ROOT/'vendor'/'water_global_def.v').read_bytes()==(ROOT/'vendor'/'global_def.v').read_bytes()
    # TD's GUI saves this attribute with a literal ampersand. Accept the
    # vendor serialization without changing the user's open project file.
    gui=ET.fromstring((ROOT.parent/'WATER_SINGLE.al').read_text(encoding='utf-8').replace('Name="UsedInP&R"','Name="UsedInP&amp;R"'))
    built=ET.parse(ROOT/'project'/'WATER_SINGLE.al').getroot()
    def project_files(root,directory):return [(directory/f.get('Path')).resolve() for f in root.findall('./Source_Files/*/File')]
    assert project_files(gui,ROOT.parent)==project_files(built,ROOT/'project'),'GUI and build projects differ'
    report=ROOT/'project'/'WATER_SINGLE_pr.timing';bit=ROOT/'project'/'WATER_SINGLE.bit';area=ROOT/'project'/'WATER_SINGLE_phy.area'
    gate=ROOT/'project'/'WATER_SINGLE_gate.area'
    for p in [report,bit,area,gate]:assert p.stat().st_mtime>=inputs['start'],f'Stale output: {p}'
    text=report.read_text(encoding='utf-8',errors='replace')
    setup=re.search(r'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns',text)
    hold=re.search(r'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns',text)
    assert setup and hold
    setup_values=list(map(float,setup.groups()));hold_values=list(map(float,hold.groups()))
    assert min(setup_values)>=0 and min(hold_values)>=0,dict(setup=setup_values,hold=hold_values)
    log=(ROOT/'validation'/'td_build.log').read_text(encoding='utf-8',errors='replace')
    assert 'PHY-5079' not in log,'Clock net uses local routing'
    assert not re.search(r'\bERROR:',log),'TD error in build log'
    coverage=re.search(r'STA coverage\s*:\s*([\d.]+)%',text);assert coverage and float(coverage[1])>=99
    util={}
    for label in ['lut','reg','bram','bram32k','dsp']:
        match=re.search(r'^#'+label+r'\s+(\d+)\s+out of\s+(\d+)',area.read_text(),re.M)
        if match:util[label]=dict(used=int(match[1]),available=int(match[2]))
    assert util and all(v['used']<=v['available'] for v in util.values())
    assert util['lut']['used']<12811,'LUT optimization must reduce routed LUT use against the 12811 baseline'
    assert util['dsp']['used']<=7,'Shared arithmetic exceeded seven-DSP target'
    assert util['bram32k']['used']<=10,'Shared caches exceeded RAM32K target'
    assert util['bram']['used']<=49,'RAM9K regression against seven-DSP LUT baseline'
    native_map=re.search(r'\|\s+native_cache\s*\|water_native_cache\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)',gate.read_text())
    assert native_map and int(native_map[1])==6,'Native cache must map to six physical RAM9K blocks'
    verification=json.loads((ROOT/'validation'/'rtl_tests.json').read_text(encoding='utf-8'))
    assert verification.get('full'),'Full validation is required'
    for path,digest in verification['inputs'].items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,f'Test input changed: {path}'
    tests={}
    test_cache=json.loads((ROOT/'validation'/'rtl_cache.json').read_text(encoding='utf-8'))
    for name in ['arithmetic','cache','surface','photos','effects','math','reader','fx_reader','frame','expand','edge','scene','transition','blend','native','scaler_pacing','multires','bandwidth','bandwidth_dwell','bandwidth_native','bandwidth_metal','bandwidth_tunnel']:
        for path,digest in test_cache[name]['inputs'].items():
            assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,f'Cached test dependency changed: {name}: {path}'
        result=(ROOT/'validation'/(name+'_test.log')).read_text(encoding='utf-8',errors='replace')
        assert 'PASS ' in result and 'FATAL:' not in result,f'Validation not passed: {name}'
        recorded=next(t for t in verification['tests'] if t['test']==name)
        assert result==recorded['stdout']+recorded['stderr'],f'Test log differs from manifest: {name}'
        tests[name]=result.strip()
    for result in json.loads((ROOT/'validation'/'adapter_tests.json').read_text(encoding='utf-8')):
        for path,digest in result['inputs'].items():
            assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,f'Adapter input changed: {path}'
        log_text=(ROOT/'validation'/(result['test']+'_test.log')).read_text(encoding='utf-8')
        assert log_text==result['stdout']+result['stderr'] and 'PASS ' in log_text and 'FATAL:' not in log_text
        tests[result['test']]=log_text.strip()
    assert all(n in tests for n in ['mapper','expand_recovery','storage','serializer','sd_clock','audio_chain','audio_output','sample_phase','handoff','music_select','origin']),'Adapter/storage validation missing'
    audit=ROOT/'validation'/'timing_check.rpt'
    assert audit.stat().st_mtime>=inputs['start'],'Timing audit must match the current build'
    audit_text=audit.read_text(encoding='utf-8',errors='replace')
    for check in ['no clock','clock definition','invalid constraint','pll/clock buffer clock constraints','combinational loops']:
        match=re.search(r'checking '+re.escape(check)+r'\((\d+)\)',audit_text)
        assert match and int(match[1])==0,f'Timing audit failed: {check}'
    comparison={}
    baseline=ROOT/'validation'/'baseline_lut.area'
    if baseline.exists():
        baseline_text=baseline.read_text(encoding='utf-8')
        for label,entry in util.items():
            match=re.search(r'^#'+label+r'\s+(\d+)\s+out of',baseline_text,re.M)
            if match:
                before=int(match[1]);after=entry['used']
                comparison[label]=dict(before=before,after=after,saved=before-after,
                                       saved_percent=round((before-after)*100/before,2) if before else 0)
    assets=json.loads((ROOT/'validation/assets.json').read_text(encoding='utf-8'))
    music_entry=next(entry for entry in assets if entry['output'].upper().endswith('.AUD'))
    music=ROOT/'tf_assets'/music_entry['output']
    assert len(list((ROOT/'tf_assets').glob('*.AUD')))==1,'Only the selected AUD belongs in the TF asset set'
    music_data=music.read_bytes();music_hash=hashlib.sha256(music_data).hexdigest()
    assert music_hash==music_entry['sha256'],'Music asset differs from its manifest'
    pcm_bytes,rate,bits,channels=struct.unpack_from('<IIHH',music_data,8)
    assert music_data[:8]==b'SXAUD001' and (rate,bits,channels)==(48000,16,2) and pcm_bytes%4==0 and len(music_data)>=512+pcm_bytes
    chosen=re.search(r"SELECTED_AUDIO_BYTES=32'd(\d+)",(ROOT/'rtl/top_water_single.v').read_text())
    assert chosen and int(chosen[1])==pcm_bytes,'Compiled music selector does not match the delivered AUD'
    for p in [bit,report,area,gate]:shutil.copy2(p,ROOT/'delivery'/p.name)
    shutil.copy2(bit,ROOT.parent/'WATER_SINGLE.bit')
    output=dict(bit_sha256=hashlib.sha256(bit.read_bytes()).hexdigest(),setup=setup_values,hold=hold_values,
                sta_coverage=float(coverage[1]),resources=util,resolution=[1280,720],pixel_clock_hz=75000000,
                refresh_hz=75000000/(1650*750),animation_update_hz=75000000/(3300*750),
                internal_resolution=[1280,720],framebuffer_words=460800,effect_resolution=[640,720],effect_framebuffer_words=230400,
                slot_words=691200,slot_bases=[0,691200,1382400],allocated_sdram_words=2073600,
                horizontal_reconstruction='Native four-pixel groups are read atomically with the same address cadence as effect blocks; native RGB565 outside displaced 4-pixel blocks; even-pixel-centred [1,2,1]/4 filtered 640x720 effect plane, 2x RGB565 interpolation with cross-word lookahead and right-edge clamp inside waves and all transitions',
                sdram_user_clock_hz=50000000,media_clock_hz=50000000,tf_spi_clock_hz=12500000,
                bit=str(ROOT.parent/'WATER_SINGLE.bit'),project=str(ROOT.parent/'WATER_SINGLE.al'),
                hardware_validation='User reported good effects with baseline d9fc8735fafa7ceaee87793f8aa6a55eb6af5b6c6f1c1706e11ec2c30d07f908. This release reduces LUT through exact squaring, Booth alpha products, shared ribbon calculation and tighter proven lighting bounds. Current changes and preceding seven-DSP baseline require board verification',
                bmp_input='24-bit uncompressed bottom-up BMP: 640x480, 1280x720, 1920x1080 and legal sizes within 640..1920 by 360..1080. Runtime FPGA scaler produces 1280x720; native-sized sources bypass interpolation. The loader additionally derives a horizontally even-pixel-centred [1,2,1]/4 filtered 640x720 effect plane; both planes are generated on FPGA from the same BMP.',
                monitor_diagnostic='User reports internal TPG visible in the 75MHz nominal-720p60 mode; nominal-720p30 mode black.',
                sdram_read_contract='Four consecutive aligned words per SDR burst. Only sequential row requests reach SDRAM; all ripple/random reads use a 32-row on-chip cache.',
                row_cache=dict(old_effect_rows=32,new_effect_rows=2,native_rows=2,native_pixels_per_read=4,native_ram9k_blocks=6,ram32k_blocks=10,shared_destination_native=True,maximum_vertical_displacement=14),
                optimization=dict(baseline='Seven-DSP build 91e24a4abf33f4db42b7bd3a71c83314ba1a43c2b0eecd054a6814a3afcfbecb; 12811 routed LUT. This baseline itself was not board-confirmed',
                                  resources=comparison,geometry_engines=1,coordinate_interval_clocks=2,
                                  blend_channel_multipliers=0,video_fifo_words=1024,
                                  effect_shared_dsp=1,metadata_token_banks=2,coordinate_lut_fifo_entries=16,
                                  square_implementation='Symmetric bit-pair square with carry-save compression; sqrt comparison reuses subtraction sign',
                                  progress_square_storage='ROM spare addresses 257..511, explicit 0/256 endpoints',
                                  ribbon_shared_classification=True,ribbon_shared_wave_product=True,
                                  folded_sine_magnitudes=17,lighting_unsigned_result_bits=7,
                                  reciprocal_rom_ports=1,reciprocal_reads_per_coordinate=2,folded_surface_pixels_per_unit=2,
                                  result_equivalence='Integer coordinates, RGB565 blend rounding, lighting and image data remain bit-exact; external pipeline latency and throughput are unchanged',
                                  blend_implementation='Four-row radix-four Booth recoding with carry-save reduction; exact rounding and four-edge latency',
                                  constant_products='Explicit shift/add for 3x, 5x, 6x and power-of-two coordinate arithmetic',
                                  native_cache_packing='512 direct four-pixel entries plus a 128-entry two-slot byte-dual-port tail. Six RAM9K, unchanged atomic read latency; destination half-plane and native dwell share the same store.'),
                audio=dict(pcm_fifo_samples=2048,refill_level=1536,format='48000Hz signed16 stereo, left shifted by 8 into HDMI signed24',
                           diagnostic_key='KEY2 short: drop; hold 1s: music -> digital zero -> 1kHz -18dBFS sine -> music',
                           status_digit='Second digit from right: mode in bits3:2, sticky PCM underrun in bit1, SDR read timeout in bit0',
                           source_hiss='Previous BGM1 was confirmed clean by the user. Current selection is Time is Broken, decoded locally to 48kHz signed16 stereo without denoising or gain changes. AUD payload is byte-exact to the converted WAV; source quality and live playback still need listening verification.'),
                transition_handoff='All eleven effects use progress 0..256 and show a native destination frame before commit. Native and effect paths use one four-pixel coordinate per block. SW2 still offers a forced effect-plane comparison.',
                transition_mode_bits=4,coordinate_map_latency_clocks=6,
                transition_sequence_ids=[6,0,1,2,3,4,5,7,8,9,10],
                transition_effects=['WaterDrop multi-ring', 'Scroll curl with reflected texture, shadow and specular edge', 'Orthographic card flip with projected texture and illuminated rim', 'Eight staggered ribbons with curved edges and eased motion', 'Eight staggered column flips', 'Accordion compression with illuminated folds', 'Liquid metal front with local refraction and silver rim', 'Circular energy portal with refraction', 'Slanted glass fragments with staggered horizontal movement', 'Horizontal tunnel with contracting and expanding texture projections', 'Viscous curved split with independently displaced halves'],
                music_asset=dict(file=str(music),sha256=music_hash,data_bytes=pcm_bytes,duration_seconds=pcm_bytes/192000,selection='Only the chosen header length is published; previous BGM1 is ignored'),
                tests=tests,memory_model='Aligned four-word burst assertions, ordered 14-cycle responses, periodic 6/768 refresh stalls and 256-cycle write turns; additional actual packer/FIFO/write-FSM readback integration.',
                source_hashes=inputs['hashes'])
    (ROOT/'delivery'/'release.json').write_text(json.dumps(output,indent=2),encoding='utf-8')
    print(json.dumps({k:output[k] for k in ['bit_sha256','setup','hold','sta_coverage','resources','bit','project']}));print(f'Release verified: {len(tests)} tests')

if __name__=='__main__':main()
