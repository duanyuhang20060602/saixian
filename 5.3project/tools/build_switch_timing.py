"""Build the measurement variant and publish distinctly named local firmware."""
from pathlib import Path
import argparse,datetime,json,os,shutil
from build_v4_port import ROOT,build,digest,inputs
from verify_saved_project import verify
from test_switch_timing import JOBS
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--work',type=Path,required=True)
 parser.add_argument('--board',choices=('a','b','both'),default='both')
 parser.add_argument('--td-root',type=Path);args=parser.parse_args()
 verify(strict=False)
 tests=json.loads((ROOT/'tests/switch_timing_results/results.json').read_text(encoding='utf-8'))
 assert {r['test'] for r in tests}==set(JOBS) and all(r['passed'] for r in tests)
 assert all(digest(ROOT/p)==h for r in tests for p,h in r['inputs_sha256'].items()),'Stale test inputs'
 os.environ['SAIXIAN_TEMP_ROOT']=(args.work/'temp').resolve().as_posix()
 if args.td_root:os.environ['SAIXIAN_TD_ROOT']=args.td_root.resolve().as_posix()
 manifest=json.loads((ROOT/'package_manifest.json').read_text(encoding='utf-8'))
 profiles={r['board']:r for r in manifest['release_builds']}
 records=[]
 for board in (('a','b') if args.board=='both' else (args.board,)):
  accepted=json.loads((ROOT/profiles[board]['record']).read_text(encoding='utf-8'))
  os.environ['SAIXIAN_PLACE_SEED']=accepted.get('place_seed_override') or ('17' if board=='a' else '11')
  os.environ['SAIXIAN_PHYSICAL_STRATEGY']=accepted.get('physical_strategy',{}).get('name','TimingUltraEmbedded')
  build(board,args.work)
  record=json.loads((args.work/f'builds/board_{board}/result.json').read_text(encoding='utf-8'))
  assert record['status']=='passed' and record['inputs_sha256']==inputs('board_'+board)
  records.append(record)
 records=[]
 for board in ('a','b'):
  path=args.work/f'builds/board_{board}/result.json'
  if not path.exists():print('Board '+board+' not built yet; firmware pair has not been published.');return
  record=json.loads(path.read_text(encoding='utf-8'))
  if record['status']!='passed':print('Board '+board+' not passed yet; firmware pair has not been published.');return
  assert record['inputs_sha256']==inputs('board_'+board)
  records.append(record)
 stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
 destination=ROOT/'releases'/('switch_timing_'+stamp);destination.mkdir(exist_ok=False)
 files={}
 for record in records:
  board=record['board'].upper();name='PHOTO_BOARD_'+board+'_SWITCH_TIMING.bit'
  shutil.copy2(record['bit']['path'],destination/name);files[name]=digest(destination/name)
  for kind in ('timing','area'):shutil.copy2(record[kind]['path'],destination/Path(record[kind]['path']).name)
 report={'variant':'switch timing, original 48-frame transition','base_commit':'bcfb810ad621cde50475b83e6c3bf046098cea1f',
         'hardware_validation':'pending','unit':'decimal milliseconds','boards':records,'tests':tests,'files_sha256':files}
 (destination/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 shutil.copy2(ROOT/'SWITCH_TIMING.txt',destination/'SWITCH_TIMING.txt')
 print('Measurement firmware: '+str(destination),flush=True)
if __name__=='__main__':main()
