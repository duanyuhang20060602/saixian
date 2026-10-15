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
 value.update(award_revision=3,award_entry_key='A KEY4 short toggle; KEY1 photos only',
  award_crc_checks=[],award_crc_enabled=False,photo_directory_capacity=6,award_directory_id=6,award_independent_of_photo_count=True,
  failed_award_load='keep visible frame, show banner and diagnostic error; KEY4 retry',
  simulation_acceptance='See award_v3_validation.json; native sector/memory endpoints modeled',
  hardware_acceptance='V3 pending physical A/B board validation; V2 DLT blank root cause unconfirmed')
 manifest.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8');boards.append(value)

assert digest(ROOT/'award_media/AWARD720.DLT')=='4adf1b6696401faa8e4c7f6d165b3a2d67ffdc49d4d933ac2781056f1b0e5c5b'
tests=[]
for report,names in [
 ('award_v3_results.json',{'tb_award_notice_v3','tb_award_mode_v3','tb_award_catalog_v3'}),
 ('dlt_v3_engine_results.json',{'tb_dlt_reader','tb_dlt_faults','tb_dlt_cache'}),
 ('award_regression.json',{'tb_award_headers','tb_bmp','tb_award_control'})]:
 records=json.loads((ROOT/'tests/results'/report).read_text(encoding='utf-8'))
 selected=[v for v in records if v['test'] in names]
 assert {v['test'] for v in selected}==names
 for v in selected:
  log=ROOT/'tests/results'/(v['test']+'.log')
  text=log.read_text(encoding='utf-8')
  assert v['passed'] and 'PASS' in text and 'FATAL' not in text
  tests.append({**v,'log_sha256':digest(log)})

# Retain provenance for the original asset and orientation. These are prior
# V2 runs, explicitly not presented as fresh V3 test executions.
base=ROOT.parent/'dual_award_dlt_v2'
baseline=ROOT/'tests/baseline_v2';baseline.mkdir(exist_ok=True)
for name in ['dlt_reader_results.json','dlt_fault_results.json','tb_dlt_reader.log','tb_dlt_faults.log','tb_dlt_orientation.log']:
 shutil.copy2(base/'tests/results'/name,baseline/name)
shutil.copy2(base/'delivery/award_validation.json',baseline/'award_validation.json')
for name in ['common/photo_sd/photo_dlt_header.v']:
 assert digest(ROOT/name)==digest(base/name),name+' decoder changed, fresh asset validation required'

validation={'revision':3,'built_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'boards':[{k:b[k] for k in ['role','file','sha256','timing_ns','resources']} for b in boards],
 'tests_run_for_v3':tests,'inherited_v2_evidence':'tests/baseline_v2: prior orientation checks; header unchanged; decoder has fresh V3 real-asset and fault tests',
 'dlt_crc_enabled':False,'dlt_full_payload_prepass':False,
 'dlt_sha256':digest(ROOT/'award_media/AWARD720.DLT'),
 'hardware_validation':'pending; V2 DLT blank root cause requires V3 diagnostic observations',
 'limitations':['Raw contiguous sectors, not FAT fragmented-file traversal','Search first 512 MiB','Sector and memory endpoints modeled in simulation']}
(OUT/'award_v3_validation.json').write_text(json.dumps(validation,indent=2)+'\n',encoding='utf-8')
(OUT/'delivery_manifest.json').write_text(json.dumps({'revision':3,'boards':boards},indent=2)+'\n',encoding='utf-8')
selected=set()
for role in ['board_a','board_b']:
 selected.update(files(role))
 selected.add(ROOT/'projects'/role/'src/td_project/sources.json')
 selected.add(OUT/(role+'_manifest.json'));selected.add(OUT/(role+'_build_sources.json'))
 for name in [role+'_PHOTO_'+role.upper()+'_pr.timing',
              role+'_PHOTO_'+role.upper()+'_phy.area',role+'_award_build.log']:
  selected.add(OUT/name)
selected.update(OUT/v['file'] for v in boards)
selected.update(ROOT/'award_media'/n for n in ['AWARD720.DLT','AWARD720_DLT.json','base_tagged_rgb565.bin'])
selected.update((ROOT/'tools').glob('*.py'));selected.update((ROOT/'tests').glob('*.v'))
selected.update(baseline.glob('*'))
for v in tests:selected.add(ROOT/'tests/results'/(v['test']+'.log'))
for name in ['award_v3_results.json','dlt_v3_engine_results.json','award_regression.json']:selected.add(ROOT/'tests/results'/name)
selected.update(ROOT/n for n in ['AWARD_DLT_V3.md','baseline.json'])
selected.update(OUT/n for n in ['award_v3_validation.json','delivery_manifest.json'])
archive=OUT/'DUAL_720P_AWARD_DLT_V3_NOCRC_SOURCE_BITS_AND_MEDIA.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for path in sorted(selected):z.write(path,path.relative_to(ROOT).as_posix())
 z.write(ROOT/'AWARD_DLT_V3.md','README.md')
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'sha256':digest(archive),'fresh_tests':len(tests)},indent=2))
