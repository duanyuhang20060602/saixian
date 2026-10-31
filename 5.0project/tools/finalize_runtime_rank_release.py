"""Publish FPGA-only runtime rank/defaults after exact source and STA checks."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil
from build_v4_port import ROOT,inputs,LIMITS

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def write(path,data):Path(path).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
def current(record):
 table=record.get('source_sha256',record.get('inputs_sha256',{}));assert table
 return all((Path(p) if Path(p).is_absolute() else ROOT/p).is_file() and sha(Path(p) if Path(p).is_absolute() else ROOT/p)==h for p,h in table.items())

def main():
 p=argparse.ArgumentParser();p.add_argument('--a-work',type=Path,required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args()
 work=a.work.resolve();assert work.is_relative_to(Path('E:/Codex/Work'))
 directory=a.a_work.resolve()/'builds/board_a';ar=read(directory/'result.json')
 assert ar['board']=='a' and ar['status']=='passed' and ar['inputs_sha256']==inputs('board_a')
 assert ar['inputs_unchanged'] and ar['toolchain_unchanged'] and ar.get('local_flow_unchanged',True)
 assert all(sha(Path(p))==h for p,h in ar['toolchain_sha256'].items())
 assert all(ar['resources'][k]<=limit for k,limit in LIMITS.items())
 assert ar['timing_ns']['SWNS']>=0 and ar['timing_ns']['HWNS']>=0 and ar['timing_ns']['STNS']==ar['timing_ns']['HTNS']==0
 for kind in ('bit','area','timing'):assert sha(ar[kind]['path'])==ar[kind]['sha256']
 slices=re.findall(r'(\d+)\s+mslices',(directory/'build.log').read_text(errors='replace'));assert slices and int(slices[-1])<=4900
 prior=ROOT/'releases/match_score_20261031';old=read(prior/'validation.json');br=read(prior/'board_b_build.json')
 assert br['board']=='b' and br['status']=='passed'
 for relative,h in br['inputs_sha256'].items():assert sha(ROOT/relative)==h,'Changed B input: '+relative
 for board,record in [('a',read(prior/'board_a_build.json')),('b',br)]:
  for relative,h in record['inputs_sha256'].items():
   if '/constraints_source/' in relative:assert sha(ROOT/relative)==h,'Changed clocks or pins: '+relative
 assert br['timing_ns']['SWNS']>=0 and br['timing_ns']['HWNS']>=0 and br['timing_ns']['STNS']==br['timing_ns']['HTNS']==0
 b_bit=ROOT/'releases/PHOTO_BOARD_B_5_0.bit';assert sha(b_bit)==br['bit']['sha256']
 tests={r['test']:dict(r) for r in old['tests'] if r['passed'] and current(r)}
 paths=['final_protocol14/results.json','aligned_pipeline03/results.json','final_transport09/results.json',
        'legacy_controls02/results.json','final_native08/results.json','av_stream_reset_final/results.json',
        'audio_launch01/results.json','match_serial_final/results.json','match_resources_final/results.json','title_final/results.json','shared_timeout01/results.json']
 for relative in paths:
  for record in read(work/relative):
   assert record['passed'] and current(record),'Failed/stale test: '+record['test']
   assert sha(record['log'])==record['log_sha256'];tests[record['test']]=dict(record)
 for record in read(work/'glass_geometry02/results.json')['cases']:
  assert record['passed'] and current(record),'Failed/stale glass geometry proof'
  record=dict(record,log=str(work/'glass_geometry02/map_equivalence.log'))
  assert sha(record['log'])==record['log_sha256'];tests[record['test']]=record
 required={'control','keys','numbers','serial','render','keys_tick','legacy_keys','font_native','video','title_index_match','hmi_spi_compact','hmi_uart',
   'fifo_8','fifo_2048','spi_registered','award_column','award_column_shared','priority','columns_native',
   'complete_hmi_parser','complete_hmi_rank_pixels','rank_metadata_pipeline','fpga_rank_transport','fpga_legacy_controls',
   'native_rank_parser','native_rank_pixels','native_rank_pipeline','av_stream_reset','shared_hmi_timeout','map_equivalence'}
 assert required==set(tests),(required-set(tests),set(tests)-required)
 destination=ROOT/'releases/runtime_rank_20261031';assert not destination.exists(),'Do not overwrite a completed release'
 destination.mkdir();(destination/'validation').mkdir()
 for name,record in tests.items():
  saved=destination/'validation'/f'{name}.log';shutil.copy2(record['log'],saved);record['saved_log']=saved.relative_to(ROOT).as_posix()
 write(destination/'board_a_build.json',ar);shutil.copy2(prior/'board_b_build.json',destination/'board_b_build.json')
 reuse=dict(board='b',mode='reuse_exact_qualified879_firmware',baseline_commit=old['base_commit'],source_inputs_verified=len(br['inputs_sha256']),
  inputs_sha256=br['inputs_sha256'],extra_inventory_inputs={p:h for p,h in inputs('board_b').items() if p not in br['inputs_sha256']},
  note='New runtime parser and rank ROMs are A-only. Every original recorded B input and the B source list remain byte-identical.',
  bit_sha256=sha(b_bit),resources=br['resources'],timing_ns=br['timing_ns'],local_recompile=False,hardware_validation='pending')
 write(destination/'board_b_reuse.json',reuse)
 manifest_path=ROOT/'package_manifest.json';manifest=read(manifest_path)
 backup=work/'before_publication';backup.mkdir(exist_ok=True)
 for relative in ['package_manifest.json','VERSION','releases/PHOTO_BOARD_A_5_0.bit']:
  target=backup/relative;target.parent.mkdir(parents=True,exist_ok=True);assert not target.exists();shutil.copy2(ROOT/relative,target)
 # Keep the uncompiled screen experiment recoverable outside the FPGA project.
 # The user stopped screen work; never replace their original MOUSE_C source.
 assert sha(ROOT/'hmi/MOUSE_C.HMI')=='a971cc8182b216c700fbcc17962d563dbb654781181cb876a84ac595bdfa00da'
 candidate=ROOT/'hmi/MOUSE_C_complete.HMI'
 if candidate.is_file():
  screen_report=read(work/'source_report.json');assert sha(candidate)==screen_report['output_sha256']
  target=work/'unreleased_screen/MOUSE_C_complete.HMI'
  assert candidate.resolve().is_relative_to(ROOT.resolve()) and target.resolve().is_relative_to(work)
  target.parent.mkdir(exist_ok=True);assert not target.exists();shutil.move(str(candidate),str(target))
 a_bit=ROOT/'releases/PHOTO_BOARD_A_5_0.bit';shutil.copy2(ar['bit']['path'],a_bit)
 for board,record in [('a',ar),('b',br)]:
  for kind in ('area','timing'):
   source=Path(record[kind]['path']) if board=='a' else prior/Path(record[kind]['path'].replace('\\','/')).name
   assert sha(source)==record[kind]['sha256'];shutil.copy2(source,destination/source.name);shutil.copy2(source,ROOT/'releases'/source.name)
 shutil.copy2(directory/'build.log',destination/'board_a_build.log')
 validation=dict(build_id='runtime-rank-20261031',version='5.0',passed=True,fpga_only=True,
  scope='Current FPGA UART/defaults/ranking pixels/native RAM plus retained qualified regressions; exact original B inputs verified.',
  base_commit=old['base_commit'],previous_release='match_score_20261031',hardware_validation='pending',screen_modified=False,screen_flashed=False,
  defaults=dict(title='100米',ticker='欢迎来到运动会',auto_enable=1,effect_select=0,edge_enable=1),
  resources=dict(a=ar['resources'],b=br['resources']),timing_ns=dict(a=ar['timing_ns'],b=br['timing_ns']),a_mslices=int(slices[-1]),
  b_local_recompile=False,b_reuse_record='releases/runtime_rank_20261031/board_b_reuse.json',test_count=len(tests),tests=list(tests.values()),
  development_checks=[read(work/'development_check.json')],
  prior_historical_failed_regressions=old.get('historical_failed_regressions',[]),
  firmware_sha256={'releases/PHOTO_BOARD_A_5_0.bit':sha(a_bit),'releases/PHOTO_BOARD_B_5_0.bit':sha(b_bit)})
 write(destination/'validation.json',validation)
 (ROOT/'VERSION').write_text('5.0\nbuild_id=runtime-rank-20261031\nhardware_validation=pending\n',encoding='utf8')
 manifest.update(version='5.0',build_id=validation['build_id'],source_state='FPGA-only runtime ranking, default text, native RAM/column optimizations. A rebuilt; exact original B artifact retained.',
  source_commit=None,release_tag=None,source_release=destination.relative_to(ROOT).as_posix(),hardware_validation='pending',saved_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
  release_files=validation['firmware_sha256'],current_recorded_test_count=len(tests),firmware_layout='canonical_only',
  release_builds=[dict(board=r['board'],resources=r['resources'],timing_ns=r['timing_ns'],bit_sha256=r['bit']['sha256'],record=(destination/f'board_{r["board"]}_build.json').relative_to(ROOT).as_posix()) for r in [ar,br]],
  package_checks=dict(local_compilation_performed=True,both_boards_recompiled=False,b_upstream_input_hashes_verified=len(br['inputs_sha256']),
    current_tests_passed=len(tests),hardware_validation='pending',screen_tft_generated=False,screen_flashed=False,new_markdown_or_archives=False,
    historical_failures_recorded=len(validation['prior_historical_failed_regressions'])))
 inventory={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and p!=manifest_path}
 manifest.update(files_sha256=inventory,file_count=len(inventory),saved_rtl_files=sum(1 for base in (ROOT/'common',ROOT/'src') for _ in base.rglob('*.v')))
 for entry in manifest.get('source_files',[]):
  if entry.get('saved') in inventory:entry['saved_sha256']=inventory[entry['saved']]
 write(manifest_path,manifest)
 from verify_saved_project import verify
 result=verify(strict=True);write(work/'final_verification.json',result)
 write(work/'completion.json',dict(completed=True,active_project=str(ROOT),release=str(destination),firmware=validation['firmware_sha256'],
  tests=len(tests),resources=validation['resources'],timing_ns=validation['timing_ns'],screen_flashed=False,hardware_validation='pending',github_uploaded=False))
 print(json.dumps(dict(passed=True,tests=len(tests),resources=validation['resources'],timing_ns=validation['timing_ns'],firmware=validation['firmware_sha256']),indent=2))
if __name__=='__main__':main()
