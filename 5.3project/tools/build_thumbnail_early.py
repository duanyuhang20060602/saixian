"""Build early-thumbnail A; retain B only after checking identical build inputs."""
from pathlib import Path
import argparse,datetime,json,os,shutil
from build_v4_port import ROOT,build,digest,inputs
from verify_saved_project import verify
from test_thumbnail_early import JOBS
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--work',type=Path,required=True)
 parser.add_argument('--previous-release',type=Path,required=True)
 parser.add_argument('--td-root',type=Path);parser.add_argument('--reuse-build',action='store_true');args=parser.parse_args()
 verify(strict=False)
 previous=read(args.previous_release/'validation.json')
 b=next(r for r in previous['boards'] if r['board']=='b')
 assert b['status']=='passed' and b['inputs_sha256']==inputs('board_b'),'B inputs differ'
 b_bit=args.previous_release/'PHOTO_BOARD_B_PREFETCH_OVERLAP.bit'
 assert digest(b_bit)==b['bit']['sha256']==previous['files_sha256'][b_bit.name]
 tests=read(ROOT/'tests/thumbnail_early_results/results.json')
 assert {r['test'] for r in tests}==set(JOBS)
 for result in tests:
  assert result['passed'] and all(digest(ROOT/p)==h for p,h in result['inputs_sha256'].items())
 profile=next(r for r in read(ROOT/'package_manifest.json')['release_builds'] if r['board']=='a')
 accepted=read(ROOT/profile['record'])
 os.environ['SAIXIAN_TEMP_ROOT']=(args.work/'temp').resolve().as_posix()
 if args.td_root:os.environ['SAIXIAN_TD_ROOT']=args.td_root.resolve().as_posix()
 os.environ.setdefault('SAIXIAN_PLACE_SEED','23')
 os.environ.setdefault('SAIXIAN_PHYSICAL_STRATEGY',accepted['physical_strategy']['name'])
 if not args.reuse_build:build('a',args.work)
 a=read(args.work/'builds/board_a/result.json')
 assert a['status']=='passed' and a['inputs_sha256']==inputs('board_a')
 for kind in ('bit','area','timing'):assert digest(Path(a[kind]['path']))==a[kind]['sha256']
 assert b['inputs_sha256']==inputs('board_b')
 stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
 destination=ROOT/'releases'/('thumbnail_early_'+stamp);destination.mkdir(exist_ok=False)
 files={}
 def copy(source,name):
  shutil.copy2(source,destination/name);files[name]=digest(destination/name)
 copy(b_bit,b_bit.name);copy(Path(a['bit']['path']),'PHOTO_BOARD_A_THUMBNAIL_EARLY.bit')
 for name in ('PHOTO_BOARD_B_phy.area','PHOTO_BOARD_B_pr.timing'):copy(args.previous_release/name,name)
 for kind in ('area','timing'):copy(Path(a[kind]['path']),Path(a[kind]['path']).name)
 for name in ('SWITCH_TIMING.txt','PREFETCH_OVERLAP.txt','THUMBNAIL_EARLY.txt'):copy(ROOT/name,name)
 for result in tests:
  name=result['test']+'.log';copy(ROOT/'tests/thumbnail_early_results'/name,name)
 report={'variant':'A early thumbnail preparation during transition; B prefetch overlap retained',
         'hardware_validation':'pending','base_commit':'bcfb810ad621cde50475b83e6c3bf046098cea1f',
         'previous_release':str(args.previous_release.resolve()),'B_reused_with_identical_inputs':True,
         'boards':[a,b],'tests':tests,'files_sha256':files}
 (destination/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 print('Validated firmware pair: '+str(destination),flush=True)
if __name__=='__main__':main()
