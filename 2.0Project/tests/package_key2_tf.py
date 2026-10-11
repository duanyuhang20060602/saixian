"""Package only a timing-pass, simulation-pass build with matching sources."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess, zipfile

ROOT=Path(__file__).resolve().parents[1]
RELEASE=ROOT/'releases/key2_tf_static_fix_20261011'
WORK=ROOT/'validation/key2_tf_20261010'
TESTS=['tb_static_eco_truth','tb_static_bus_ownership','tb_result_controls','tb_key2_short_long','tb_key2_tf_flow','tb_shared_media_fifo',
       'tb_stream_crc','tb_mapper_equivalence','tb_cue_equivalence','tb_decoder','tb_axis',
       'tb_first_hold','tb_loading_policy','tb_volume_boost',
       'tb_audio_repair','tb_audio_repair_controls','tb_audio_repair_osd','tb_audio_repair_integration','tb_crc_network',
       'tb_repair_equivalence','tb_loader_header','tb_descriptor_bounds','tb_cache_crc','tb_medal_equivalence','tb_scaler_equivalence',
       'tb_preload_controls','tb_photo_retention','tb_loader_hint','tb_preload_lifecycle','tb_video_handoff','tb_tf_preload','tb_preload_crc',
       'tb_enhance_term_equivalence','tb_scan_target_equivalence','tb_enhance','tb_enhance_detail','tb_enhance_numeric','tb_enhance_tap_range',
       'tb_bmp_payload_limits','tb_audio_header_stream','tb_media_header','tb_fifo_full_equivalence']
def test_folder(name):
    return WORK/({'tb_tf_preload':'preload_mode','tb_preload_crc':'preload_crc'}[name]) if name in {'tb_tf_preload','tb_preload_crc'} else WORK
for name in TESTS:
    folder=test_folder(name)
    log=(folder/f'{name}.log').read_text(encoding='utf-8')
    assert 'PASS' in log and 'FATAL' not in log, name
timing=(RELEASE/'routed_timing.rpt').read_text(encoding='utf-8')
setup=re.search(r'SWNS:\s*([-\d.]+)ns,\s*STNS:\s*([-\d.]+)ns',timing)
hold=re.search(r'HWNS:\s*([-\d.]+)ns,\s*HTNS:\s*([-\d.]+)ns',timing)
assert setup and hold
assert float(setup[1])>=0 and float(setup[2])==0 and float(hold[1])>=0 and float(hold[2])==0
bit=RELEASE/'SAIXIAN_KEY2_TF_20261010.bit'
assert bit.read_bytes()==(ROOT/'src/td_project'/bit.name).read_bytes()
build_log=ROOT/'src/td_project/key2_tf_build.log'
build_text=build_log.read_text(encoding='utf-8')
seed_match=re.search(r'set_param place seed (\d+)',build_text)
assert seed_match and not re.search(r'(?m)^\S+ ERROR:',build_text)
place_seed=int(seed_match[1])
for source in (ROOT/'src').rglob('*.v'):
    assert source.stat().st_mtime <= bit.stat().st_mtime, f'HDL newer than bit: {source}'

shutil.copy2(ROOT/'examples/TF卡新增动图/TROPHY.DLT',RELEASE/'TROPHY.DLT')
shutil.copy2(ROOT/'KEY2_TF动图使用说明.md',RELEASE/'使用说明.md')
logdir=RELEASE/'verification';logdir.mkdir(exist_ok=True)
shutil.copy2(build_log,logdir/'td_build.log')
for name in TESTS:
    folder=test_folder(name)
    shutil.copy2(folder/f'{name}.log',logdir/f'{name}.log')
baseline_log=WORK/'static_fix_baseline/tb_static_bus_ownership.log'
baseline_text=baseline_log.read_text(encoding='utf-8')
assert 'TF stole an issued photo read' in baseline_text
shutil.copy2(baseline_log,logdir/'pre_fix_static_bus_ownership_expected_failure.log')

suffixes={'.v','.vh','.sdc','.adc','.cwc','.mif','.hex','.tcl','.ipc'}
sources=[p for p in (ROOT/'src').rglob('*') if p.is_file() and p.suffix.lower() in suffixes
         and p != ROOT/'src/td_project/top_out.v']
sources+=[ROOT/'src/td_project/SAIXIAN_KEY2_TF_20261010.al',ROOT/'build_key2_tf.ps1',ROOT/'README.md',ROOT/'KEY2_TF动图使用说明.md']
sources+=[p for p in (ROOT/'tests').rglob('*') if p.is_file() and p.suffix.lower() in {'.v','.py'}]
sources+=[p for p in (ROOT/'examples/TF卡新增动图').rglob('*') if p.is_file()]
sources+=[ROOT/'doc/音频修复锐化版_20261010.md']
sources+=[p for p in (ROOT/'src/td_project/static_bus_baseline').iterdir() if p.is_file()]
sources=sorted(set(sources))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
board_record_path=RELEASE/'board_confirmation.json'
board_record=json.loads(board_record_path.read_text(encoding='utf-8')) if board_record_path.exists() else None
board_verified=bool(board_record and board_record.get('passed') is True
                    and board_record.get('bit_sha256','').lower()==sha(bit))
report={
 'baseline_commit':'d23efefcd6d098a4d055ec064981315d4418196a',
 'animation_commit':'88a9b975abdb36660ec29d92ec9f6c58842a6531',
 'local_branch':'fpga/key2-tf-animation','place_seed':place_seed,'board_verified':board_verified,
 'board_confirmation':board_record,
 'build_packing':{'gate_pack_effort':'high','gate_opt_area':'high','gate_map_mode':'area_prior',
                  'rtl_dsp_pack_zreg':'on','place_pack_mode':'area','place_relaxation':0.97},
 'build_origin':'native TD 6.2 incremental ECO on SHA256-pinned timing-pass preload checkpoint; exact two RTL edits and complete implemented netlist delta checked before release',
 'changes':['TF physical bus select masks local FIFO clear/command-clear; arbiter IDLE and transaction admission remain baseline behavior',
            'native ECO changes only one existing bus-select LUT and two unused inputs; all other implemented logic and timing-pass placement preserved',
            'TF preload starts during results; podium retained until verified first frame is ready',
            'retained photo buffers allow exit without SD reinitialization, rescanning or reloading the current photo',
            'DLT cache survives normal exit/reentry; actual card reset invalidates cache and metadata',
            'two photo buffers plus sprint background; TF partition starts at word 1382400, max file 1937408 bytes',
            'record discovered DLT sector and skip validated BMP/AUD extents during first scan',
            'independent photo/TF video FIFOs and shared SDRAM arbitration preserve photos during preload',
            'video handoff occurs after 64 clocks within vertical blanking, with shared raster timing',
            'removed extra initial 1-second hold',
            'restored local morning V4 audio repair and ninth setting/font',
            'volume 0 stays mute; gains 0,.25,.5,.625,.75,.875,1,1.125,1.25 with saturation',
            'CRC32 common XOR network is bit-equivalent to polynomial reference',
            'shared audio arithmetic is sample-exact against morning V4; 320-clock minimum spacing',
            'registered spike magnitudes split audio threshold arithmetic; clean-sample phases and output latency unchanged',
            'enhancement clamps before narrow arithmetic; all 4088 feasible detail/strength/mode combinations match prior RTL',
            'AUD scan skip/target prepared before sector end; 5000 wrapped full-width address/length/limit cases match prior arithmetic',
            'real card reset also clears stale TF presentation state; normal exit retains cached media',
            'audio FIFO full flag uses modulo next-pointer equality; all 262144 pointer pairs preserve full/write gating',
            'shared upload/readback CRC and precheck/decode CRC retain both passes',
            'removed redundant fixed-pattern bus startup test; all actual-data CRC checks retained',
            'registered volume product adds one video clock; accepted HDMI samples unchanged',
            'medal center subtraction moved earlier; 16384 exact geometry/latency comparisons',
            'scaler data capture enable simplified; 60 image/cycle-equivalence comparisons'],
 'setup_slack_ns':float(setup[1]),'hold_slack_ns':float(hold[1]),
 'setup_total_violation_ns':float(setup[2]),'hold_total_violation_ns':float(hold[2]),
 'tests_passed':TESTS,'original_frame_decoder_coverage':'27 frames + loop delta, both mirrored buffers',
 'static_bus_regression':{'pre_fix_reproduced':True,'pre_fix_failure':'TF stole an issued photo read',
                          'delay_mem_clocks':48,'photo_reads_issued':100391,'photo_responses_checked':100352,
                          'clear_cycles':4803,'command_clear_handshakes':301,'refresh_stalls':True},
 'integrated_bus_video_coverage':'2-frame native 480x480 fixture, 1382400 exact RGB565 pixels, concurrent photo reads, retained photo partition, cached reentry with zero SD reads/reinitialization, refresh and masked writes; actual corrupt payload rejected, cancel/retry and actual card-reset invalidation/reload',
 'full_27_frame_realtime_integrated_simulation_completed':False,
 'bit_sha256':sha(bit),'tf_asset_sha256':sha(RELEASE/'TROPHY.DLT'),
 'source_sha256':{p.relative_to(ROOT).as_posix():sha(p) for p in sources},
}
(RELEASE/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
proofdir=logdir/'static_bus_eco'
proofdir.mkdir(exist_ok=True)
for name in ('baseline_phy.v','patched_phy.v','routed_phy.v'):
    shutil.copy2(WORK/'static_bus_eco'/name,proofdir/name)
report['static_eco_proof_sha256']={p.name:sha(p) for p in proofdir.glob('*.v')}
(RELEASE/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
archive=RELEASE/'SAIXIAN_KEY2_TF_20261010_source.zip'
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED) as z:
    for path in sources:z.write(path,'2.0Project/'+path.relative_to(ROOT).as_posix())
    for path in (bit,RELEASE/'TROPHY.DLT',RELEASE/'validation.json',RELEASE/'routed_timing.rpt',RELEASE/'resource.rpt'):
        z.write(path,'2.0Project/'+RELEASE.relative_to(ROOT).as_posix()+'/'+path.name)
    if board_record_path.exists():
        z.write(board_record_path,'2.0Project/'+RELEASE.relative_to(ROOT).as_posix()+'/'+board_record_path.name)
    for path in sorted(logdir.rglob('*')):
        if path.is_file():
            z.write(path,'2.0Project/'+RELEASE.relative_to(ROOT).as_posix()+'/verification/'+path.relative_to(logdir).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    for name,digest in report['source_sha256'].items():
        assert hashlib.sha256(z.read('2.0Project/'+name)).hexdigest()==digest, name
print(json.dumps({'bit':str(bit),'source_archive':str(archive),'tests':len(TESTS),'setup_ns':report['setup_slack_ns'],'hold_ns':report['hold_slack_ns']},ensure_ascii=False))
