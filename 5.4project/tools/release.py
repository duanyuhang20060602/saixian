from pathlib import Path
import json,hashlib,sys,re,shutil,zipfile,time,datetime
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'delivery';OUT.mkdir(parents=True,exist_ok=True)
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def files(role):
    td=ROOT/'src'/role/'td_project'
    paths=json.loads((td/'sources.json').read_text(encoding='utf-8'))
    found={(td/p).resolve() for p in paths}
    found.update((td.parent/'user_source/constraints_source').glob('*'))
    if role=='board_a':found.update([ROOT/'common/photo_menu_font.mif',ROOT/'common/audio_ui/saixian_font_rom.mif'])
    if role=='board_a':found.update((ROOT/'common/audio_ui').glob('saixian_av_*'))
    found.update((td.parent/'user_source/hdl_source/include').glob('*.v'))
    found.update((td.parent/'user_source/hdl_source/IP').glob('*.tcl'))
    found.update([td/'build_board.tcl',td/f'PHOTO_{role.upper()}.al'])
    return sorted(p for p in found if p.is_file())
def hashes(role):return {p.relative_to(ROOT).as_posix():digest(p) for p in files(role)}
def snapshot(role):
    value={'started':time.time(),'source_sha256':hashes(role)}
    (OUT/f'{role}_build_sources.json').write_text(json.dumps(value,indent=2),encoding='utf-8')
def collect(role):
    saved=json.loads((OUT/f'{role}_build_sources.json').read_text(encoding='utf-8'))
    assert saved['source_sha256']==hashes(role),'Source changed during or after build'
    td=ROOT/'src'/role/'td_project';name=f'PHOTO_{role.upper()}'
    bit=td/(name+'.bit');timing=td/(name+'_pr.timing');area=td/(name+'_phy.area')
    assert bit.stat().st_mtime>=saved['started'],'Stale bitstream'
    report=timing.read_text(encoding='utf-8',errors='replace')
    def metric(tag):
        m=re.search(tag+r':\s*([-\d.]+)ns',report);assert m,tag;return float(m[1])
    values={key:metric(key) for key in ['SWNS','STNS','HWNS','HTNS']}
    assert values['SWNS']>=0 and values['HWNS']>=0 and values['STNS']==0 and values['HTNS']==0,values
    resources={}
    text=area.read_text(encoding='utf-8',errors='replace')
    for key in ['lut','reg','bram9k','bram32k','dsp']:
        m=re.search(r'^\s*#'+key+r'\s+(\d+)',text,re.M);assert m,key;resources[key]=int(m[1])
    dest=OUT/(name+'_720P_V3_1_BOOT_RECOVERY_LINK50M.bit');shutil.copy2(bit,dest)
    for src in [timing,area,td/'award_build.log']:shutil.copy2(src,OUT/(role+'_'+src.name))
    result={'role':role,'file':dest.name,'sha256':digest(dest),'bytes':dest.stat().st_size,'timing_ns':values,
            'link_clock_hz':50000000,'enhancement_enabled':role=='board_b','sharpness_enabled':role=='board_b','image_processing_location':'board_b','hdmi_settings_menu':True,'unified_settings_menu':True,'color_modes':['RGB565 four A slots / three B slots','RGB888 two slots per board'],'rgb888_packing':'four pixels / three MSB-first 32-bit words','rgb888_transition':'all six selected effects','default_color_mode':'RGB565','audio_visual_modes':['spectrum','waveform'],'control_keys_location':'board_a','b_display_raw_pinned':'settings_only','cache_scheduling':'playback_sender_window/settings_display_pin','settings_pause_prefetch':True,'settings_coalesce_ms':50,'audio_stage':2,'audio_diagnostics':True,'native_menu_rgb_bypass':role=='board_a','audio_processing_location':'board_b','spectrum_location':'board_a','audio_volume_steps':9,'event_controller_location':'board_a','audio_scan_policy':'first photo foreground, resumable directory scan in cache idle time','audio_spi_hz':3750000,'audio_format':'SXAUD001 PCM 48k stereo16','audio_next_key':'A KEY2 in carousel outside settings','audio_payload_crc16':False,'audio_signal_pins':'J2-24/27/28/31','image_processing_reference':'d27ae79126429f1a25a65e42f8fe95571da5c0df:2.0Project','default_enhancement':1,'default_detail_strength':1,'frame_crc_enabled':False,'pixel_link':'c13937b high/low falling-edge launch, combinational ready',
            'sdram_read_data_delay_cycles':1 if role=='board_a' else 0,'sdram_read_data_delay_cycles_rgb888':1,'rgb888_b_read_alignment':'one-clock capture, valid unchanged' if role=='board_b' else 'existing one-clock capture','rgb888_alignment_hardware_status':'candidate awaiting board confirmation','resources':resources,'built_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'source_sha256':saved['source_sha256'],'a_cache_frames':4,'a_rgb888_cache_frames':2,'b_rgb888_cache_frames':2,'rgb888_frame_bytes':2764800,'source_resolution_overlay':True,'b_cached_hit_during_load':True,'a_cache_window':'current, next, next2, next3','tf_multiblock_read':True,'tf_continuous_bytes':True,'tf_clock_hz':25000000,'simulation_acceptance':'AUDIO2 functional simulations not run','hardware_acceptance':'AUDIO2 awaiting board validation'}
    result.update(award_mode=True,award_revision=4,award_asset='AWARD720.DLT',award_direct_dlt=True,award_crc_checks=[],
                  award_tag_transport='SXDLT003 header; internal source-width bit15',
                  award_render_location='board_a',award_processing_bypass='board_b',
                  award_transition='immediate at video blanking; no tag interpolation',
                  award_pause_key='A KEY2 outside settings; music next remains on HMI',
                  award_auto_advance=False,award_hdmi_latency_cycles=26,
                  source_resolution_overlay='photos only; metadata width flag masked',
                  simulation_acceptance='See tests/results/award_results.json and award_regression.json',
                  hardware_acceptance='FFT/wave/repair candidate awaiting physical A/B board validation',
                  rgb888_alignment_hardware_status='baseline user-reported blue tint fixed; brief photo-switch black field unresolved')
    result.update(version='V3.1 boot recovery candidate',plot_background='75% photograph',rgb888_transition_modes='all six; four-pixel packed groups',fade_midpoint='three true-black frames; one fade stage',neutral_pipeline='15-clock replacement verified against original',startup_audio_policy='first track buffered, no full-catalog wait',startup_audio_buffer_samples=512,startup_release='first visible frame after loading',startup_animation='existing black loading UI',
                  audio_visual_algorithm='single-board 1024-point stereo FFT / Hann / 32 bands',
                  audio_waveform='1024 samples; 256 groups of stereo min/max; double-buffered',
                  audio_repair=True,audio_repair_default=False,audio_repair_location='board_b before cue mix and volume',
                  audio_repair_latency_samples=32,audio_repair_crossfade_samples=256,
                  audio_spi_prepare_bit=16,audio_repair_control_bit=0,
                  award_revision='V3.1 accepted baseline',award_crc_checks=[],
                  simulation_acceptance='tests/results/boot_audio_sync_results.json, audio_port_results.json and award_v4_results.json',
                  hardware_acceptance='Boot recovery awaits board confirmation; high-color switching artifacts unresolved',display_fifo_words=1024,receiver_handshake='restored board-tested combinational ready',read_completion='restored fixed turnaround gap',startup_fault_diagnostic='first image error latched; A shows 480SEC while boot waits (S=control state, E=first error)',prefetch_display_reserve_words=512,rgb888_prefetch_policy='yield new write bursts below display reserve',rgb888_alignment_hardware_status='baseline color alignment confirmed; FIFO starvation reproduced and eliminated in modeled concurrent-prefetch simulation')
    (OUT/f'{role}_manifest.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(role,values,resources)
def package():
    data=[json.loads((OUT/f'{r}_manifest.json').read_text(encoding='utf-8')) for r in ['board_a','board_b']]
    for value in data:assert value['source_sha256']==hashes(value['role']),'Sources differ from delivered build'
    (OUT/'delivery_manifest.json').write_text(json.dumps({'baselines':json.loads((ROOT/'baseline.json').read_text(encoding='utf-8')),'boards':data},indent=2),encoding='utf-8')
    selected=set()
    for role in ['board_a','board_b']:selected.update(files(role))
    selected.update(ROOT/name for name in ['README.md','A_FOUR_CACHE.md','PLAYBACK_CONTROLS.md','VALIDATION.md','COMPARISON_720.md','SOURCE_COMPARISON.md','FLOW_REVIEW.md','TF_READ_OPTIMIZATION.md','IMAGE_PROCESSING.md','HDMI_SETTINGS_MENU.md','AUDIO_STAGE1.md','AUDIO_STAGE2.md','HIGH_COLOR_MODE.md','RGB888_READ_ALIGNMENT.md']);selected.update(ROOT.glob('*.json'));selected.update(ROOT.glob('*.ps1'));selected.update(ROOT.glob('*.svg'))
    selected.update((ROOT/'tools').glob('*.py'));selected.update((ROOT/'tests').glob('*.v'));selected.update((ROOT/'tests').glob('*.hex'))
    # The optional pattern test is shipped as a regression dependency only.
    selected.add(ROOT/'common/top_photo_pattern_b.v')
    selected.add(ROOT/'AWARD_DLT_V4.md')
    selected.update(ROOT/'award_media'/n for n in ['AWARD720.DLT','AWARD720_DLT.json','base_tagged_rgb565.bin'])
    selected.update(ROOT/'tests/results'/n for n in ['award_results.json','award_regression.json',
      'dlt_reader_results.json','dlt_fault_results.json','dlt_cache_results.json'])
    validation=json.loads((OUT/'award_validation.json').read_text(encoding='utf-8'))
    selected.update(ROOT/'tests/results'/(t['test']+'.log') for t in validation['tests'])
    selected.add(OUT/'delivery_manifest.json')
    selected.add(OUT/'award_validation.json')
    for role in ['board_a','board_b']:
        selected.update([OUT/f'{role}_manifest.json',OUT/f'{role}_build_sources.json'])
        for suffix in ['timing','area','log']:selected.update(OUT.glob(f'{role}_*.{suffix}'))
    selected.update(OUT/value['file'] for value in data)
    for role in ['board_a','board_b']:selected.add(ROOT/'src'/role/'td_project/sources.json')
    with zipfile.ZipFile(OUT/'DUAL_720P_AWARD_DLT_V4_SOURCE_BITS_AND_MEDIA.zip','w',zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(selected):archive.write(path,path.relative_to(ROOT).as_posix())
    print('Packaged',OUT/'DUAL_720P_AWARD_DLT_V4_SOURCE_BITS_AND_MEDIA.zip')
if __name__=='__main__':
    if sys.argv[1]=='snapshot':snapshot(sys.argv[2])
    elif sys.argv[1]=='collect':collect(sys.argv[2])
    elif sys.argv[1]=='package':package()

