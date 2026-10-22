from pathlib import Path
import datetime,hashlib,json,shutil,zipfile
from release import ROOT,OUT,files,hashes,digest

boards=[]
for role in ['board_a','board_b']:
 manifest=OUT/(role+'_manifest.json')
 value=json.loads(manifest.read_text(encoding='utf-8'))
 assert value['source_sha256']==hashes(role),role+' source differs from delivered bit'
 assert digest(OUT/value['file'])==value['sha256'],role+' bit hash mismatch'
 assert min(value['timing_ns']['SWNS'],value['timing_ns']['HWNS'])>=0
 assert value['timing_ns']['STNS']==value['timing_ns']['HTNS']==0
 value.update(award_revision=4,award_entry_key='A KEY4 short toggle; KEY1 photos only',
  award_crc_checks=[],award_crc_enabled=False,boot_animation='A black background spinner and stage progress; frame-ready one-shot exit',award_bmp_compatibility=False,award_initial_hold_frames=0,photo_directory_capacity=6,award_directory_id=6,award_independent_of_photo_count=True,
  failed_award_load='keep visible frame, show banner and diagnostic error; KEY4 retry',
  simulation_acceptance='See award_v4_validation.json; native sector/memory endpoints modeled',
  hardware_acceptance='V4 pending physical A/B board validation; entry hold removed')
 manifest.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8');boards.append(value)

assert digest(ROOT/'award_media/AWARD720.DLT')=='4adf1b6696401faa8e4c7f6d165b3a2d67ffdc49d4d933ac2781056f1b0e5c5b'
tests=[]
for report,names in [
 ('award_v4_results.json',{'tb_award_notice_v3','tb_boot_v4','tb_award_entry_v4','tb_award_headers','tb_award_mode_v4','tb_award_catalog_v3'}),
 ('dlt_cache_v4_results.json',{'tb_dlt_cache'}),
 ('award_results.json',{'tb_award_render'}),
 ('award_regression.json',{'tb_award_pixels','tb_award_fx'})]:
 records=json.loads((ROOT/'tests/results'/report).read_text(encoding='utf-8'))
 selected=[v for v in records if v['test'] in names]
 assert {v['test'] for v in selected}==names
 for v in selected:
  log=ROOT/'tests/results'/(v['test']+'.log')
  text=log.read_text(encoding='utf-8')
  assert v['passed'] and 'PASS' in text and 'FATAL' not in text
  tests.append({**v,'log_sha256':digest(log)})

# These are prior V3 NOCRC executions, not fresh V4 runs.
base=ROOT.parent/'dual_award_dlt_v3'
baseline=ROOT/'tests/baseline_v3';baseline.mkdir(exist_ok=True)
for name in ['dlt_v3_engine_results.json','tb_dlt_reader.log','tb_dlt_faults.log']:
 shutil.copy2(base/'tests/results'/name,baseline/name)
shutil.copy2(base/'delivery/award_v3_validation.json',baseline/'award_v3_validation.json')
for name in ['common/photo_sd/photo_dlt_reader.v','common/photo_sd/photo_dlt_header.v','common/photo_color_format.v']:
 assert digest(ROOT/name)==digest(base/name),name+' changed; fresh full decoder validation required'
# Real original single-board asset and sprite bytes remain unchanged.
single=ROOT.parent.parent/'saixian-review-20261015/3.0Project/src/user_source/hdl_source'
assert digest(ROOT/'common/award_sprite_rom.v')==digest(single/'award_sprite_rom.v')

validation={'revision':4,'built_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'boards':[{k:b[k] for k in ['role','file','sha256','timing_ns','resources']} for b in boards],
 'tests_run_for_v4':tests,'inherited_v3_evidence':'tests/baseline_v3: unchanged NOCRC decoder full-asset and fault checks',
 'dlt_crc_enabled':False,'dlt_full_payload_prepass':False,
 'dlt_sha256':digest(ROOT/'award_media/AWARD720.DLT'),
 'hardware_validation':'pending; user reported entry-only pause; fixed 61-frame entry hold removed',
 'limitations':['Raw contiguous sectors, not FAT fragmented-file traversal','Search first 512 MiB','Sector and memory endpoints modeled in simulation']}
(OUT/'award_v4_validation.json').write_text(json.dumps(validation,indent=2)+'\n',encoding='utf-8')
(OUT/'delivery_manifest.json').write_text(json.dumps({'revision':4,'boards':boards},indent=2)+'\n',encoding='utf-8')
selected=set()
for role in ['board_a','board_b']:
 selected.update(files(role))
 selected.add(ROOT/'src'/role/'td_project/sources.json')
 selected.add(OUT/(role+'_manifest.json'));selected.add(OUT/(role+'_build_sources.json'))
 for name in [role+'_PHOTO_'+role.upper()+'_pr.timing',
              role+'_PHOTO_'+role.upper()+'_phy.area',role+'_award_build.log']:
  selected.add(OUT/name)
selected.update(OUT/v['file'] for v in boards)
selected.update(ROOT/'award_media'/n for n in ['AWARD720.DLT','AWARD720_DLT.json','base_tagged_rgb565.bin'])
selected.update((ROOT/'tools').glob('*.py'));selected.update((ROOT/'tests').glob('*.v'))
selected.update(baseline.glob('*'))
for v in tests:selected.add(ROOT/'tests/results'/(v['test']+'.log'))
for name in ['award_v4_results.json','dlt_cache_v4_results.json','award_results.json','award_regression.json']:selected.add(ROOT/'tests/results'/name)
selected.update(ROOT/n for n in ['AWARD_DLT_V4.md','baseline.json'])
selected.add(ROOT/'tests/results/boot_preview.png')
selected.update(OUT/n for n in ['award_v4_validation.json','delivery_manifest.json'])
archive=OUT/'DUAL_720P_AWARD_DLT_V4_NOCRC_SOURCE_BITS_AND_MEDIA.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for path in sorted(selected):z.write(path,path.relative_to(ROOT).as_posix())
 z.write(ROOT/'AWARD_DLT_V4.md','README.md')
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':digest(archive),'fresh_tests':len(tests)},indent=2))
