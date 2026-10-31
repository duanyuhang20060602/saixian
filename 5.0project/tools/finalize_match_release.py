"""Qualify the match integration and publish only the fixed5.0 firmware pair."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil
from build_v4_port import ROOT,inputs,LIMITS

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,data):Path(p).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def current_hashes(record):
 table=record.get('source_sha256',record.get('inputs_sha256',{}));assert table
 for p,h in table.items():
  path=Path(p) if Path(p).is_absolute() else ROOT/p
  assert path.is_file() and sha(path)==h,'Stale regression: '+str(path)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--a-work',type=Path,required=True);ap.add_argument('--b-delivery',type=Path,required=True);ap.add_argument('--work',type=Path,required=True);ap.add_argument('--tests',nargs='+',type=Path,required=True);a=ap.parse_args()
 work=a.work.resolve();work.mkdir(parents=True,exist_ok=True);ad=a.a_work/'builds/board_a'
 ar=read(ad/'result.json');assert ar['status']=='passed' and ar['board']=='a'
 assert ar.get('local_flow_unchanged',True)
 assert ar['inputs_unchanged'] and ar['toolchain_unchanged'] and ar['inputs_sha256']==inputs('board_a')
 assert all(sha(p)==h for p,h in ar['toolchain_sha256'].items())
 assert ar['timing_ns']['SWNS']>=0 and ar['timing_ns']['STNS']==0 and ar['timing_ns']['HWNS']>=0 and ar['timing_ns']['HTNS']==0
 assert all(ar['resources'][k]<=v for k,v in LIMITS.items())
 slices=re.findall(r'(?:PHY|RUN)-1001 : (\d+) mslices,',(ad/'build.log').read_text(errors='replace'))
 assert slices and int(slices[-1])<=4900
 for kind in ('bit','area','timing'):assert sha(ar[kind]['path'])==ar[kind]['sha256']
 bd=a.b_delivery.resolve();br=read(bd/'board_b_build.json');assert br['status']=='passed' and br['board']=='b'
 assert br['bit']['sha256']=='cd3a4ae5555f56e4d87b60ac4f55de3bf254c193c12a1e59ee2790b819054843'
 for relative,h in br['inputs_sha256'].items():assert sha(ROOT/relative)==h,'Changed B dependency: '+relative
 assert br['timing_ns']['SWNS']>=0 and br['timing_ns']['HWNS']>=0 and br['timing_ns']['STNS']==0 and br['timing_ns']['HTNS']==0
 for kind,name in [('bit','PHOTO_BOARD_B.bit'),('area','PHOTO_BOARD_B_phy.area'),('timing','PHOTO_BOARD_B_pr.timing')]:assert sha(bd/name)==br[kind]['sha256']
 # B receives the existing cue IDs1..5 and the same SPI/UART frames.
 # New A-only ROM/header files are not dependencies of B's unchanged source list.
 bcurrent=inputs('board_b');assert set(br['inputs_sha256'])<=set(bcurrent)
 b_extra={p:h for p,h in bcurrent.items() if p not in br['inputs_sha256']}
 baseline=work/'baseline/5.0project'
 for board in ('a','b'):
  for path in (ROOT/f'src/board_{board}/user_source/constraints_source').iterdir():
   if path.is_file():assert path.read_bytes()==(baseline/path.relative_to(ROOT)).read_bytes(),'Clock/pin constraints changed'
 glyph=bd/'GLYPHS.BIN';assert sha(glyph)==read(bd/'SHA256SUMS.json')['GLYPHS.BIN']
 bsources=read(ROOT/'src/board_b/td_project/sources.json')
 assert bsources==read(baseline/'src/board_b/td_project/sources.json')
 assert all((ROOT/p).read_bytes()==(baseline/p).read_bytes() for p in br['inputs_sha256'])
 # Collect only successful current tests, retaining negative historical
 # fixtures separately. No old failure is relabeled as a passing test.
 tests={}
 for path in a.tests:
  for r in read(path):
   if not r['passed']:continue
   current_hashes(r);log=Path(r['log']);assert sha(log)==r['log_sha256']
   assert r['test'] not in tests,'Duplicate validation case: '+r['test'];tests[r['test']]=r
 required={'control','keys','numbers','serial','render','keys_tick','legacy_keys','font_native','video','title_index_match','hmi_spi_compact','hmi_uart','fifo_8','fifo_2048','spi_registered','award_column','award_column_shared','priority','columns_native'}
 assert required<=set(tests),'Missing validation: '+str(required-set(tests))
 destination=ROOT/'releases/match_score_20261031';destination.mkdir(parents=True,exist_ok=True)
 (destination/'validation').mkdir(exist_ok=True)
 for name,r in tests.items():
  log=destination/'validation'/(name+'.log');shutil.copy2(r['log'],log);r['saved_log']=log.relative_to(ROOT).as_posix()
 write(destination/'board_a_build.json',ar);shutil.copy2(bd/'board_b_build.json',destination/'board_b_build.json')
 reused=dict(board='b',mode='reuse_verified879_firmware',baseline_commit='8797178900367d0686735622de20c8c22e098342',source_inputs_verified=len(br['inputs_sha256']),unchanged_source_list=True,
  inputs_sha256=br['inputs_sha256'],a_only_added_inventory_inputs=b_extra,bit_sha256=br['bit']['sha256'],original_build_record_sha256=sha(bd/'board_b_build.json'),resources=br['resources'],timing_ns=br['timing_ns'],local_recompile=False,hardware_validation='pending')
 write(destination/'board_b_reuse.json',reused)
 for board,r,source in [('a',ar,Path(ar['bit']['path'])),('b',br,bd/'PHOTO_BOARD_B.bit')]:
  shutil.copy2(source,ROOT/f'releases/PHOTO_BOARD_{board.upper()}_5_0.bit')
  for kind in ('area','timing'):
   path=Path(r[kind]['path']) if board=='a' else bd/Path(r[kind]['path'].replace('\\','/')).name
   assert sha(path)==r[kind]['sha256']
   shutil.copy2(path,destination/path.name);shutil.copy2(path,ROOT/'releases'/path.name)
 shutil.copy2(ad/'build.log',destination/'board_a_build.log')
 # Keep all inherited obsolete binaries/archives recoverable in Work, with
 # verified absolute paths. The active tree has only its two canonical bits.
 canonical={ROOT/f'releases/PHOTO_BOARD_{b}_5_0.bit' for b in ('A','B')}
 archived=[]
 for p in sorted(ROOT.rglob('*')):
  if not p.is_file() or not(p.suffix.lower()=='.zip' or p.suffix.lower()=='.bit' and p not in canonical):continue
  relative=p.relative_to(ROOT);target=work/'archived_older_deliveries'/relative
  assert p.resolve().is_relative_to(ROOT.resolve()) and target.resolve().is_relative_to(work.resolve())
  assert (baseline/relative).is_file() and sha(p)==sha(baseline/relative),'Modified inherited file: '+str(p)
  target.parent.mkdir(parents=True,exist_ok=True)
  assert not target.exists();h=sha(p);shutil.move(str(p),str(target));archived.append(dict(relative=relative.as_posix(),archive=str(target),sha256=h))
 write(destination/'archived_older_deliveries.json',archived)
 # The prior879 delivery shipped its runtime glyph library inside the zip.
 glyph=bd/'GLYPHS.BIN';assert sha(glyph)==read(bd/'SHA256SUMS.json')['GLYPHS.BIN']
 shutil.copy2(glyph,ROOT/'examples/TF卡素材/GLYPHS.BIN')
 failures=[];old_results=work/'tests_hmi/results.json'
 if old_results.exists():
  for r in read(old_results):
   if r['passed']:continue
   original_inputs_unchanged=all(sha(ROOT/p)==h and sha(baseline/p)==h for p,h in r['inputs_sha256'].items())
   assert original_inputs_unchanged
   log=work/'tests_hmi'/(r['test']+'.log');saved=destination/'validation'/('historical_'+r['test']+'.log');shutil.copy2(log,saved)
   failures.append(dict(r,classification='unchanged879_inputs_historical_test_failure',counted_as_pass=False,baseline_rerun=False,saved_log=saved.relative_to(ROOT).as_posix()))
 validation=dict(build_id='match-score-20261031',version='5.0',passed=True,scope='A match/serial-score integration, currentSD-font/UART/SPI regressions; B artifact reused from879 with every recorded input verified.',
  base_commit='8797178900367d0686735622de20c8c22e098342',feature_commit='a74f498c45c180e79134bc15f489b37c0316d810',hardware_validation='pending',screen_tft_generated=False,
  physical_profile_a=ar.get('physical_strategy'),resources={'a':ar['resources'],'b':br['resources']},timing_ns={'a':ar['timing_ns'],'b':br['timing_ns']},a_mslices=int(slices[-1]),b_local_recompile=False,
  test_count=len(tests),tests=list(tests.values()),historical_failed_regressions=failures,
  firmware_sha256={p.relative_to(ROOT).as_posix():sha(p) for p in canonical},b_reuse_record=(destination/'board_b_reuse.json').relative_to(ROOT).as_posix(),older_deliveries_archived=len(archived))
 write(destination/'validation.json',validation)
 (ROOT/'VERSION').write_text('5.0\nbuild_id=match-score-20261031\nhardware_validation=pending\n',encoding='utf-8')
 manifest=read(ROOT/'package_manifest.json')
 manifest.update(version='5.0',build_id='match-score-20261031',base_commit=validation['base_commit'],feature_commit=validation['feature_commit'],firmware_layout='canonical_only',
  source_commit=None,release_tag=None,baseline_release='Git8797178900367d0686735622de20c8c22e098342/5.0project',baseline_snapshot=str(baseline),source_release=destination.relative_to(ROOT).as_posix(),source_state='Local match integration; A rebuilt, B exact879 verified artifact retained.',hardware_validation='pending',
  saved_at=datetime.datetime.now().astimezone().isoformat(),release_files=validation['firmware_sha256'],current_recorded_test_count=len(tests),
  release_builds=[dict(board=r['board'],resources=r['resources'],timing_ns=r['timing_ns'],bit_sha256=r['bit']['sha256'],record=(destination/f'board_{r["board"]}_build.json').relative_to(ROOT).as_posix()) for r in (ar,br)],
  package_checks=dict(local_compilation_performed=True,both_boards_recompiled=False,b_upstream_input_hashes_verified=len(br['inputs_sha256']),current_tests_passed=len(tests),hardware_validation='pending',screen_tft_generated=False,new_markdown_or_archives=False,historical_failures_recorded=len(failures)))
 inventory={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and p!=ROOT/'package_manifest.json'}
 manifest.update(files_sha256=inventory,file_count=len(inventory),saved_rtl_files=sum(1 for base in (ROOT/'common',ROOT/'src') for _ in base.rglob('*.v')))
 manifest['source_files']=[item for item in manifest.get('source_files',[]) if item.get('saved') in inventory]
 for item in manifest.get('source_files',[]):
  if item.get('saved') in inventory:item['saved_sha256']=inventory[item['saved']]
 write(ROOT/'package_manifest.json',manifest)
 from verify_saved_project import verify
 result=verify(strict=True);write(work/'final_verification.json',result)
 print(json.dumps(dict(passed=True,release=str(destination),resources=validation['resources'],timing_ns=validation['timing_ns'],tests=len(tests),firmware=validation['firmware_sha256']),indent=2))
if __name__=='__main__':main()
