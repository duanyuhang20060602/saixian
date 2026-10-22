"""Freeze the timing-clean 5.4 audio integration without Markdown/archives."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil
from build_v4_port import ROOT,inputs,LIMITS
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,v):Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def prune_firmware(allowed):
 # Deliver exactly one versioned A/B pair; TD build outputs stay in Work.
 root=ROOT.resolve();keep={(root/p).resolve() for p in allowed}
 assert len(keep)==2 and all(p.is_relative_to(root/'releases') and p.is_file() for p in keep)
 removed={}
 for path in sorted(root.rglob('*')):
  if not path.is_file() or path.suffix.lower()!='.bit':continue
  resolved=path.resolve()
  assert resolved.is_relative_to(root) and not path.is_symlink(),'Unsafe firmware path: '+str(path)
  if resolved not in keep:
   removed[path.relative_to(root).as_posix()]=sha(path);path.unlink()
 # Keep historical hash evidence without listing omitted binaries as files
 # included in this delivery. Original external build records stay intact.
 removed_paths={root/p:h for p,h in removed.items()}
 for path in root.rglob('*.json'):
  if path==root/'package_manifest.json':continue
  record=read(path)
  if not isinstance(record,dict) or not isinstance(record.get('files_sha256'),dict):continue
  omitted={}
  for relative,h in list(record['files_sha256'].items()):
   candidate=(path.parent/relative).resolve()
   if candidate in removed_paths and h==removed_paths[candidate]:
    omitted[relative]=record['files_sha256'].pop(relative)
  if omitted:
   record.setdefault('omitted_firmware_sha256',{}).update(omitted)
   record['firmware_packaging_note']='Historical or duplicate firmware omitted; only the current A/B pair is delivered in the project releases directory.'
   write(path,record)
 return removed
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--work',type=Path,required=True);ap.add_argument('--a-build',type=Path,required=True);ap.add_argument('--b-build',type=Path,required=True);a=ap.parse_args()
 work=a.work.resolve();preserved=read(work/'preserved_5_3.json');baseline=Path(preserved['root'])
 assert all(sha(baseline/p)==h for p,h in preserved['files_sha256'].items()),'Frozen 5.3 baseline changed'
 records=[];mslices={}
 for board,folder in [('a',a.a_build),('b',a.b_build)]:
  r=read(folder/f'builds/board_{board}/result.json');assert r['board']==board and r['status']=='passed'
  assert r['inputs_unchanged'] and r['toolchain_unchanged'] and r.get('mapped_origin_unchanged',True)
  assert r['inputs_sha256']==inputs('board_'+board),'Stale build'
  assert all(sha(p)==h for p,h in r['toolchain_sha256'].items())
  for k in ('bit','area','timing'):assert sha(r[k]['path'])==r[k]['sha256']
  t=r['timing_ns'];assert t['SWNS']>=0 and t['HWNS']>=0 and t['STNS']==0 and t['HTNS']==0
  assert all(r['resources'][k]<=v for k,v in LIMITS.items())
  slices=re.findall(r'PHY-1001 : (\d+) mslices,',(folder/f'builds/board_{board}/build.log').read_text(errors='replace'))
  assert slices and int(slices[-1])<=4900;mslices[board]=int(slices[-1]);records.append(r)
 tests=read(work/'unchanged_regressions.json');assert len(tests)==41
 for folder,required in [('uart-tests',{'tb_audio_transport_repair','tb_boot_audio_sync'}),('animation-tests-guard',{'two_slot_cache'}),
                         ('pitch-compact',{'model','native_model','volume','keys','transport'}),('flow-compact',{'flow'}),('dlt-tests',{'guard','reader'})]:
  found={r['test']:r for r in read(work/folder/'results.json')};assert required<=set(found)
  for name in sorted(required):
   record=dict(found[name],suite=folder)
   record.setdefault('log',str(work/folder/(name+'.log')))
   tests.append(record)
 assert len(tests)==52
 for r in tests:
  assert r['passed'],r['test']
  for p,h in r['inputs_sha256'].items():assert sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h,'Stale regression '+r['test']+': '+p
  for p,h in r.get('external_inputs_sha256',{}).items():assert sha(p)==h
  assert sha(r['log'])==r['log_sha256']
 # Existing A firmware is interoperable: PCM/SPI framing and A's top/pins
 # remain exact. A is nevertheless freshly rebuilt for this saved pair.
 protocol=['common/photo_audio_link.v','common/top_photo_a.v',
           'src/board_a/user_source/constraints_source/BOARD_A_RECEIVER_pins.adc',
           'src/board_a/user_source/constraints_source/BOARD_A_RECEIVER_timing.sdc']
 assert all(sha(ROOT/p)==sha(baseline/p) for p in protocol)
 destination=ROOT/'releases/audio_pitch_20261022';destination.mkdir(parents=True,exist_ok=False)
 for r in records:
  b=r['board'];name='PHOTO_BOARD_'+b.upper();td=ROOT/f'src/board_{b}/td_project';firmware=name+'_5_4.bit'
  shutil.copy2(r['bit']['path'],ROOT/'releases'/firmware)
  write(destination/f'board_{b}_build.json',r)
  for kind in ('area','timing'):
   p=Path(r[kind]['path'])
   for parent in [destination,ROOT/'releases',td]:shutil.copy2(p,parent/p.name)
  origin=r;gate=Path(origin['work_project'])/f'src/board_{b}/td_project'/(name+'_gate.area')
  while not gate.is_file() and origin.get('mapped_origin'):
   prior=origin['mapped_origin'];assert sha(prior['result'])==prior['result_sha256'];origin=read(prior['result'])
   assert origin['inputs_sha256']==r['inputs_sha256'];gate=Path(origin['work_project'])/f'src/board_{b}/td_project'/(name+'_gate.area')
  assert gate.is_file();shutil.copy2(gate,destination/gate.name);shutil.copy2(gate,td/gate.name)
 logs=destination/'validation';logs.mkdir()
 for r in tests:
  p=logs/(r['suite']+'_'+r['test']+'.log');shutil.copy2(r['log'],p);r['saved_log']=p.relative_to(ROOT).as_posix()
 # Archive hashes of the generated independent stimuli and filter tables.
 model_stimuli={}
 for case in ('model','native_model'):
  paths=[work/'pitch-compact'/case/p for p in ('input.hex','modes.hex','results/fir_q15.npy')]
  model_stimuli[case]={str(p):sha(p) for p in paths}
 controls={'B_KEY2':{'short_release':'Cycle F0 -> F1 -> F2 -> F3 -> F4 -> F0','hold_seconds':1,'long_press':'F0 original'},
  'modes':{'F0':'Original, fixed 1183-sample effect delay plus 32-sample repair delay','F1':'Up 4 semitones','F2':'Down 5 semitones','F3':'Original + up 7 semitones','F4':'Original + up 12 semitones'},
  'B_display':'Last digit shows selected effect 0..4 when no diagnostic error is displayed.',
  'volume':{'control':'Existing A keys/touchscreen','default':5,'range':[0,8],'gain_numerators_over_8':[0,6,7,8,9,10,11,12,13],'zero':'Exact mute','clipping':'Signed 16-bit saturation','arithmetic':'Release gain factors and saturation, quantized to the existing 16-bit PCM SPI payload.'},
  'wiring':'No inter-board wiring change. B KEY2 is the on-board button at B2. A retains HDMI/touchscreen.',
  'preserved':'Existing A KEY2/KEY3, waveform/spectrum, 11 transitions, dwell ripples, trophy/spotlights, audio repair and typed page cues.',
  'integration_scope':'Port the release pitch/harmony algorithm and gain table into the full dual-board project; retain its existing display UI rather than the experimental single-board UI.',
  'audio_latency':'Fixed dry-mode DSP delay 1215 samples (25.3125 ms) plus the existing A/SPI queues and up to 256 new completed frames; this is not a measured end-to-end latency.',
  'limitations':'Time-domain experimental pitch algorithm; low bass/complex music can retain grain. No new hardware measurements.'}
 write(destination/'controls.json',controls)
 before={r['board']:r['resources'] for r in read(baseline/'package_manifest.json')['release_builds']}
 trials=[]
 for p in sorted(work.glob('build-b-*/builds/board_b/result.json')):
  t=read(p);trials.append({'record':str(p),'record_sha256':sha(p),'seed':t['place_seed_override'],'status':t['status'],'resources':t.get('resources'),'timing_ns':t.get('timing_ns')})
 upstream=read(work/'upstream_sources.json')
 assert sha(ROOT/'tests/reference/audio_pitch/saixian_audio_pitch.v')==upstream['files_sha256']['project/src/user_source/hdl_source/saixian_audio_pitch.v']
 assert sha(ROOT/'tests/reference/audio_pitch/quality_model.py')==upstream['files_sha256']['tools/quality_model.py']
 validation={'version':'5.4-audio-pitch-20261022','hardware_validation':'pending','requires_matched_pair':False,'compatible_A_firmware':['5.3','5.4'],
  'source_release':upstream['release'],'source_commit':upstream['commit'],'baseline_commit':'bcfb810ad621cde50475b83e6c3bf046098cea1f',
  'preserved_5_3':{'root':str(baseline),'file_count':len(preserved['files_sha256']),'all_hashes_verified':True},
  'resources_before':before,'resources_after':{r['board']:r['resources'] for r in records},'mslices_after':mslices,
  'timing_ns':{r['board']:r['timing_ns'] for r in records},'physical_placement_trials':trials,
  'regression_accounting':{'current_passed':len(tests),'reexecuted':11,'unchanged_reverified':41},'tests':tests,
  'native_ram_validation':'10000 stereo frames across all modes, compact dry history, RAM banking/wrap and clear; unmodified supplier ram_infer via the project adapter.',
  'effect_model_validation':'50000 stereo frames exact against the release independent fixed-point model.',
  'model_stimuli_sha256':model_stimuli,'wire_compatibility_sha256':{p:sha(ROOT/p) for p in protocol},'controls':controls,
  'architecture':{'processor':'B: repair -> pitch -> 256-frame completed queue -> existing typed cue mixer -> boosted saturating volume -> SPI -> A HDMI',
   'history':'4096 filtered stereo frames plus 2048 raw stereo frames for the fixed 1152-frame dry delay; six RAM32K blocks. Save 8 KiB without changing any accessed samples.',
   'A_external_sdram_slots':3,'B_external_sdram_slots':2,'TF_SPI_driver_changed':False,'SPI_format_changed':False,
   'media_control_retiming':'Latch the post-edge 512-byte sector predicate at input_end; all cycle-visible DLT outputs are compared against frozen 5.3 with full accepted media and malformed/overlapping boundaries.',
   'producer_clear':'Uses actual media stream-reset, track flush, abort and background-off; volume-only updates retain effect history.'}}
 validation['firmware_layout']='canonical_only'
 validation['firmware_files']={r['board'].upper():{'path':'../PHOTO_BOARD_'+r['board'].upper()+'_5_4.bit','sha256':r['bit']['sha256']} for r in records}
 validation['files_sha256']={p.relative_to(destination).as_posix():sha(p) for p in destination.rglob('*') if p.is_file()};write(destination/'validation.json',validation)
 (ROOT/'VERSION').write_text(validation['version']+'\nbaseline_version=5.3-animation-cache-20261022\n',encoding='utf-8')
 manifest=read(ROOT/'package_manifest.json');manifest.update(version='5.4',saved_at=datetime.datetime.now().astimezone().isoformat(),source_commit=None,
  source_release=destination.relative_to(ROOT).as_posix(),release_tag=None,baseline_release='../5.3project',hardware_validation='pending',
  source_state='Full dual-board 5.3 plus B audio-pitch/harmony integration; exact release-model, native RAM, transport and routed build validation.',
  change_scope='Five B pitch/harmony modes, producer PCM queue, boosted saturated volume, B KEY2 controls, lossless compact dry history, cycle-equivalent DLT sector guard retiming.',
  current_recorded_test_count=len(tests),regression_accounting=validation['regression_accounting'],audio_feature_source={'release':upstream['release'],'commit':upstream['commit']},
  release_files={f'releases/PHOTO_BOARD_{r["board"].upper()}_5_4.bit':r['bit']['sha256'] for r in records},
  release_builds=[{'board':r['board'],'resources':r['resources'],'timing_ns':r['timing_ns'],'bit_sha256':r['bit']['sha256'],'record':(destination/f'board_{r["board"]}_build.json').relative_to(ROOT).as_posix()} for r in records],
  package_checks={'local_compilation_performed':True,'both_boards_recompiled':True,'current_regressions':'52 passed: 11 reexecuted, 41 unchanged inputs/logs reverified.',
   'preserved_5_3':True,'canonical_bit_copies':'5.4 release and TD programming files match accepted records.','image_media':'Unchanged.','new_markdown_or_archives':False})
 removed=prune_firmware(manifest['release_files'])
 manifest.update(firmware_layout='canonical_only',omitted_firmware_sha256=removed)
 manifest['package_checks'].pop('canonical_bit_copies',None)
 manifest['package_checks']['canonical_firmware']='Only releases/PHOTO_BOARD_A_5_4.bit and PHOTO_BOARD_B_5_4.bit are included; exact accepted hashes verified.'
 inventory={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and p!=ROOT/'package_manifest.json'}
 assert not any(Path(p).suffix.lower() in ('.md','.zip') for p in inventory)
 manifest.update(file_count=len(inventory),files_sha256=inventory,saved_rtl_files=sum(1 for base in (ROOT/'common',ROOT/'src') for _ in base.rglob('*.v')))
 for item in manifest.get('source_files',[]):
  if item['saved'] in inventory:item['saved_sha256']=inventory[item['saved']]
 write(ROOT/'package_manifest.json',manifest)
 from verify_saved_project import verify
 verify(strict=True)
 print(json.dumps({'passed':True,'release':str(destination),'resources':validation['resources_after'],'timing_ns':validation['timing_ns'],'regressions':len(tests)},indent=2))
if __name__=='__main__':main()
