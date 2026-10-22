"""Build B overlap scheduler; reuse A only when every actual build input matches."""
from pathlib import Path
import argparse,datetime,json,os,shutil
from build_v4_port import ROOT,build,digest,inputs
from verify_saved_project import verify
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--work',type=Path,required=True)
 parser.add_argument('--measurement-release',type=Path,required=True)
 parser.add_argument('--td-root',type=Path);args=parser.parse_args()
 verify(strict=False)
 previous=read(args.measurement_release/'validation.json')
 a=next(r for r in previous['boards'] if r['board']=='a')
 assert a['status']=='passed' and a['inputs_sha256']==inputs('board_a'),'A inputs differ from reusable build'
 a_bit=args.measurement_release/'PHOTO_BOARD_A_SWITCH_TIMING.bit'
 assert digest(a_bit)==a['bit']['sha256']==previous['files_sha256'][a_bit.name]
 tests=read(ROOT/'tests/prefetch_overlap_results/results.json')
 assert {r['test'] for r in tests}=={'compare','baseline_safety','early_safety'}
 for result in tests:
  assert result['passed'] and all(digest(ROOT/p)==h for p,h in result['inputs_sha256'].items())
 timing_tests=read(ROOT/'tests/switch_timing_results/results.json')
 for result in timing_tests:
  assert result['passed'] and all(digest(ROOT/p)==h for p,h in result['inputs_sha256'].items())
 profile=next(r for r in read(ROOT/'package_manifest.json')['release_builds'] if r['board']=='b')
 accepted=read(ROOT/profile['record'])
 os.environ['SAIXIAN_TEMP_ROOT']=(args.work/'temp').resolve().as_posix()
 if args.td_root:os.environ['SAIXIAN_TD_ROOT']=args.td_root.resolve().as_posix()
 os.environ['SAIXIAN_PLACE_SEED']=accepted['place_seed_override']
 os.environ['SAIXIAN_PHYSICAL_STRATEGY']=accepted['physical_strategy']['name']
 build('b',args.work)
 b=read(args.work/'builds/board_b/result.json')
 assert b['status']=='passed' and b['inputs_sha256']==inputs('board_b')
 assert a['inputs_sha256']==inputs('board_a')
 stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
 destination=ROOT/'releases'/('prefetch_overlap_'+stamp);destination.mkdir(exist_ok=False)
 files={}
 def copy(source,name):
  shutil.copy2(source,destination/name);files[name]=digest(destination/name)
 copy(a_bit,a_bit.name)
 copy(Path(b['bit']['path']),'PHOTO_BOARD_B_PREFETCH_OVERLAP.bit')
 for name in ('PHOTO_BOARD_A_phy.area','PHOTO_BOARD_A_pr.timing'):
  copy(args.measurement_release/name,name)
 for kind in ('area','timing'):copy(Path(b[kind]['path']),Path(b[kind]['path']).name)
 for name in ('SWITCH_TIMING.txt','PREFETCH_OVERLAP.txt'):copy(ROOT/name,name)
 for result in tests:
  name=result['test']+'.log';copy(ROOT/'tests/prefetch_overlap_results'/name,name)
 report={'variant':'B early prefetch overlaps locked-slot transmit; A and transition unchanged',
         'hardware_validation':'pending','base_commit':'bcfb810ad621cde50475b83e6c3bf046098cea1f',
         'measurement_release':str(args.measurement_release.resolve()),'A_reused_with_identical_inputs':True,
         'boards':[a,b],'tests':tests,'timing_tests':timing_tests,'files_sha256':files}
 (destination/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 print('Validated firmware pair: '+str(destination),flush=True)
if __name__=='__main__':main()
