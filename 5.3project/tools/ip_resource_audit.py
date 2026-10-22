"""Measured IP choices; compare the same trophy-v5 behavior before and after."""
from pathlib import Path
import hashlib,json,re

BASELINES={
 'a':Path('E:/Codex/Work/cooperate-award-v5-build-r16/builds/board_a/result.json'),
 'b':Path('E:/Codex/Work/cooperate-award-v5-build-r12-b/builds/board_b/result.json')}
ROOT=Path(__file__).resolve().parents[1]

def slice_count(result_path):
    log=(result_path.parent/'build.log').read_text(encoding='utf-8',errors='replace')
    counts=re.findall(r'PHY-1001 : (\d+) mslices,',log)
    return int(counts[-1]) if counts else None

def audit(records,experiments):
    boards={}
    for current in records:
        board=current['board'];path=BASELINES[board]
        before=json.loads(path.read_text(encoding='utf-8'))
        assert before['status']=='passed', 'Invalid resource baseline'
        boards[board]={
          'baseline_result':str(path),
          'baseline_result_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
          'before':before['resources'],'after':current['resources'],
          'delta':{k:current['resources'][k]-v for k,v in before['resources'].items()},
          'before_timing_ns':before['timing_ns'],'after_timing_ns':current['timing_ns'],
          'before_mslices':slice_count(path),
          'after_mslices':slice_count(Path(current['work_project']).parent/'result.json')}
    choices=[
      {'scope':'A neutral/award RGB delay chains','files':['common/photo_display_pipe.v','common/photo_award_render.v'],
       'decision':'24-bit circular native eRAM; original 7/12/15 clock taps and reset masking',
       'tradeoff':'5 RAM9 replace roughly 640 flip-flops including control overhead'},
      {'scope':'A/B PCM FIFO','files':['common/photo_audio_link.v','common/top_photo_a.v','common/photo_sd_cache.v'],
       'decision':'32K PDPW storage, 2048 samples on A and 8192 on B; synchronous read enable',
       'tradeoff':'Same capacity and one-clock read latency; use dense large RAM instead of small-RAM cascading'},
      {'scope':'A victory dictionary','files':['common/saixian_battle_result_fx_pipelined.v'],
       'decision':'1024 x 32 dictionary in RAM9; index lanes unchanged',
       'tradeoff':'4 RAM9 replace 2 RAM32; released large blocks hold the full A audio FIFO'},
      {'scope':'B processing output queue','files':['common/photo_b_processing.v'],
       'decision':'32 x 32 native PDPW RAM9 with output-valid masking',
       'tradeoff':'2 RAM9; preserve credits, abort/reset, full RGB888 and effect-plane words'},
      {'scope':'B bilinear scaler','files':['common/photo_sd/bmp_read.v'],
       'decision':'3 full-width head banks remain RAM32; 3 right-edge 256-pixel tails use RAM9',
       'tradeoff':'6 RAM32 + 6 RAM9 replace 12 RAM32; retain all 1280 pixels and 24-bit channels'},
      {'scope':'B FFT capture','files':['common/audio_ui/saixian_audio_visualizer.v'],
       'decision':'32 x 1024 capture in 2 RAM32 instead of 4 RAM9',
       'tradeoff':'Storage, FFT schedule, stereo handling and extrema unchanged'},
      {'scope':'A fade arithmetic','files':['common/fluid/water_edge.v'],
       'decision':'Native packed MULT9X9C lanes with registered output',
       'tradeoff':'Isolated synthesis: 339 LUT/150 FF/2 DSP -> 315 LUT/104 FF/3 DSP; whole-design packing may differ'}]
    retained=[
      {'scope':'Award sprite ROM','decision':'Keep inferred four-read implementation (4 RAM9)',
       'reason':'Packed 2 RAM32 candidate consumes scarcer large RAM and exceeded the A quota alongside the PCM configuration'},
      {'scope':'Native HDMI/SDRAM asynchronous FIFOs','decision':'Retain IP, widths, clocks, depth and CDC boundaries',
       'reason':'Already hardware RAM; reducing capacity would change burst/deadline protection'},
      {'scope':'Water caches, reciprocal ROMs and spotlight rows','decision':'Retain RAM ports and coefficient precision',
       'reason':'Preserve independent accesses, latency, exact interpolation and display deadlines'},
      {'scope':'Enhancement luma line buffers','decision':'Retain the two independently read and written 1280 x 8 RAM buffers',
       'reason':'Both taps update together at pixel rate; sharing one RAM requires additional ports, packing or a faster clock, not a type-only saving'},
      {'scope':'Small state tables, counters and short marker/control pipelines','decision':'Keep registers or distributed RAM',
       'reason':'Block RAM would spend whole blocks or require extra ports/reset emulation for little stored data'},
      {'scope':'RAM port mode alone','decision':'DP -> PDPW rejected as a stand-alone optimization',
       'reason':'Measured 24 x 1024 remains 2 RAM32 in either mode; width/depth/type allocation produced the gains'}]
    if '_dict_packed16.mif' in (ROOT/'common/saixian_battle_result_fx_pipelined.v').read_text(encoding='utf-8'):
        choices[2]={'scope':'A sprint/victory dictionaries',
                    'files':['common/saixian_battle_result_fx_pipelined.v','tools/prepare_dictionary_ip.py',
                             'src/board_a/user_source/hdl_source/saixian_sprint_atlas_dict_packed16.mif',
                             'src/board_a/user_source/hdl_source/saixian_victory_atlas_dict_packed16.mif'],
                    'decision':'Pack each dictionary as 2048 x 16; true dual-port reads low/high halves together',
                    'tradeoff':'One full RAM32 per 1024 x 32 dictionary instead of two half-empty RAM32; frees two RAM32 for the A PCM FIFO without spending RAM9; same two-clock atlas latency'}
    if 'MULT9X9C' not in (ROOT/'common/fluid/water_edge.v').read_text(encoding='utf-8'):
        packed=choices.pop()
        retained.append({'scope':packed['scope'],'decision':'Retain inferred exact multiply implementation',
                         'reason':'Packed-lane experiment trades additional scarce DSP blocks for a small LUT/FF reduction; full-design timing and headroom take precedence',
                         'experiment':packed})
    if 'photo_award_delay video_delay' not in (ROOT/'common/photo_award_render.v').read_text(encoding='utf-8'):
        choices[0]={'scope':'A neutral RGB delay','files':['common/photo_display_pipe.v'],
                    'decision':'24-bit 16-word PDPW RAM9 circular queue, original 15 clocks and reset masking',
                    'tradeoff':'2 RAM9 replace the 360-bit pixel shift chain plus small pointer/valid overhead'}
        retained.append({'scope':'A award 7/12-clock RGB taps','decision':'Retain the short register pipeline',
                         'reason':'The tested eRAM replacement needs 3 RAM9 and constrained placement; the selected combination keeps these blocks available'})
    menu_encoded='palette_rgb' in (ROOT/'common/photo_settings_overlay.v').read_text(encoding='utf-8')
    if menu_encoded:
        choices.append({'scope':'A fixed menu colors','files':['common/photo_settings_overlay.v'],
                        'decision':'Delay a three-bit index for seven constant colors; decode at the existing output tap',
                        'tradeoff':'Standalone synthesis 317 LUT/472 FF -> 297 LUT/109 FF, same RAM/DSP; exact pixels and 4/21-clock configurations checked against frozen RGB pipeline'})
    trials=[]
    for path in sorted(experiments.glob('build-r*/builds/board_*/result.json')):
        result=json.loads(path.read_text(encoding='utf-8'))
        if result['status']=='running':continue
        trials.append({'result':str(path),'board':result['board'],'status':result['status'],
                      'strategy':result.get('physical_strategy',{}).get('name'),
                      'seed':result.get('place_seed_override'),'resources':result.get('resources'),
                      'timing_ns':result.get('timing_ns'),'inputs_sha256':result['inputs_sha256']})
    return {'comparison_basis':'Same trophy-v5 visuals, resolution, clock constraints, precision and queue capacities; physical reports',
            'optimality':'Best measured selection among the retained-function IP configurations tried here; no proof of a global minimum',
            'hardware_validation':'pending','boards':boards,'accepted':choices,'retained_or_rejected':retained,'full_design_trials':trials,
            'ram_synthesis_matrix':json.loads((experiments/'ram-matrix/results.json').read_text()),
            'fade_synthesis_matrix':json.loads((experiments/'edge-matrix/results.json').read_text()),
            'menu_palette_synthesis':json.loads((experiments/'menu-palette/area_comparison.json').read_text()) if menu_encoded else None}
