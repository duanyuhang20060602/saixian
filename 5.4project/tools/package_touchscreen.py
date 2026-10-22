"""Deliver a fresh, timing-passing touch A with the exact baseline B."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,zipfile
from build_v4_port import ROOT,inputs,digest
BASE='17778ae8ebc84d9bb9618219143e76b3d5711815'
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--build',required=True,type=Path);parser.add_argument('--out',default='delivery_touchscreen_next');args=parser.parse_args()
 record_path=args.build/'builds/board_a/result.json';record=json.loads(record_path.read_text(encoding='utf-8'))
 assert record['status']=='passed' and record['inputs_unchanged'] and record['toolchain_unchanged']
 assert record['inputs_sha256']==inputs('board_a'),'Build source is stale'
 assert record['timing_ns']['STNS']==record['timing_ns']['HTNS']==0
 assert record['timing_ns']['SWNS']>=0 and record['timing_ns']['HWNS']>=0
 tests=json.loads((ROOT/'tests/touchscreen_results/results.json').read_text(encoding='utf-8'))
 assert len(tests)==16 and all(t['passed'] for t in tests)
 for t in tests:
  for path,h in t['inputs_sha256'].items():assert digest(ROOT/path)==h,'Test source is stale: '+path
 # B is reused only if every declared B input remains byte-exact to the base.
 repo=ROOT.parent
 b_inputs=inputs('board_b')
 # Shared ROMs are included by inputs(); verify the full current B input set.
 for path in b_inputs:
  data=subprocess.check_output(['git','show',BASE+':5.0project/'+path],cwd=repo)
  assert hashlib.sha256(data).hexdigest()==b_inputs[path],'Baseline B input changed: '+path
 b=ROOT/'releases/PHOTO_BOARD_B_5_0.bit'
 base_b=subprocess.check_output(['git','show',BASE+':5.0project/releases/PHOTO_BOARD_B_5_0.bit'],cwd=repo)
 assert hashlib.sha256(base_b).hexdigest()==digest(b)
 a=Path(record['bit']['path']);assert digest(a)==record['bit']['sha256']
 out=ROOT/args.out;out.mkdir(exist_ok=False)
 for src,name in [(a,'PHOTO_BOARD_A_5_0_TOUCHSCREEN.bit'),(b,'PHOTO_BOARD_B_5_0_BASELINE.bit'),(ROOT/'hmi/MOUSE.HMI','MOUSE.HMI'),(repo/'TOUCHSCREEN.md','TOUCHSCREEN.md')]:shutil.copy2(src,out/name)
 shutil.copy2(record_path,out/'board_a_build.json')
 for test in tests:
  for ending in ('.log','_compile.log'):
   src=ROOT/'tests/touchscreen_results'/(test['test']+ending)
   if src.is_file():shutil.copy2(src,out/src.name)
 # Source package contains current RTL, TD projects, ROMs, constraints, tools
 # and tests, plus the original baseline manifests and media.
 source_archive=out/'SAIXIAN_5_0_TOUCHSCREEN_SOURCE.zip'
 with zipfile.ZipFile(source_archive,'w',zipfile.ZIP_DEFLATED) as z:
  for src in ROOT.rglob('*'):
   if not src.is_file() or src.name=='refine_touchscreen_route.py':continue
   rel=src.relative_to(ROOT)
   if (rel.parts[0]=='releases' or rel.parts[0].startswith('delivery_touchscreen')) or '__pycache__' in rel.parts:continue
   if src.suffix.lower() in ('.bit','.vvp','.db','.dmp','.log','.logw','.area','.timing','.ts','.zip'):continue
   z.write(src,'5.0project/'+rel.as_posix())
  z.write(repo/'TOUCHSCREEN.md','TOUCHSCREEN.md')
 for kind in ('timing','area'):shutil.copy2(record[kind]['path'],out/Path(record[kind]['path']).name)
 summary={'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=repo,text=True).strip(),'baseline_commit':BASE,'hardware_validation':'pending','board_a':record,
          'board_b':{'reused_from':BASE,'sha256':digest(b),'all_inputs_match_baseline':True},'tests':tests,
          'files_sha256':{p.name:digest(p) for p in out.iterdir() if p.is_file()}}
 (out/'validation.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
 with zipfile.ZipFile(out/'SAIXIAN_5_0_TOUCHSCREEN.zip','w',zipfile.ZIP_DEFLATED) as z:
  for p in out.iterdir():
   if p.name!='SAIXIAN_5_0_TOUCHSCREEN.zip':z.write(p,p.name)
 print(out)
if __name__=='__main__':main()
