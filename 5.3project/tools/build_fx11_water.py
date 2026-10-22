"""Build/stage the verified A/B pair; output only bitstreams and machine-readable evidence."""
from pathlib import Path
import argparse,json,shutil,os
from build_v4_port import ROOT,build,digest,inputs
from test_fx11_water import SUITE
WORK=Path('E:/Codex/Work/cooperate-fx11-water-20261019-r16-seed19')
TESTS=Path('E:/Codex/Work/cooperate-fx11-water-tests-20261018')
def stage(work,b_work,tests,regressions):
    records=[json.loads((base/f'builds/board_{b}/result.json').read_text()) for b,base in [('a',work),('b',b_work)]]
    validation=json.loads((tests/'results.json').read_text())
    assert {r['test'] for r in validation}==set(SUITE),'Incomplete effect regression suite'
    from test_v4_port import JOBS
    regression=json.loads((regressions/'results.json').read_text())
    assert {r['test'] for r in regression}==set(JOBS)-{'tb_v4_transition_48'},'Incomplete subsystem regressions'
    for result in validation+regression:
        assert result['passed'] and result['inputs_unchanged'],result['test']
        assert all(digest(ROOT/p)==h for p,h in result['inputs_sha256'].items()),'Stale test '+result['test']
        assert all(digest(Path(p))==h for p,h in result.get('external_inputs_sha256',{}).items()),'Changed DSP simulation model'
        if 'stimuli_sha256' in result:
            assert all(digest(tests/p)==h for p,h in result['stimuli_sha256'].items()),'Changed reference vectors'
    for record in records:
        assert record['status']=='passed' and record['inputs_sha256']==inputs('board_'+record['board']),'Stale or failed build'
        assert digest(Path(record['bit']['path']))==record['bit']['sha256'],'Changed bitstream'
    destination=ROOT/'delivery/fx11_water_20261019'
    destination.mkdir(parents=True,exist_ok=False)
    artifacts={}
    for record in records:
        filename='PHOTO_BOARD_'+record['board'].upper()+'_720P_FX11_DWELL_WATER.bit'
        shutil.copy2(record['bit']['path'],destination/filename)
        # TD's normal download command resolves the project-name bitstream.
        canonical=ROOT/f'src/board_{record["board"]}/td_project'/('PHOTO_BOARD_'+record['board'].upper()+'.bit')
        shutil.copy2(record['bit']['path'],canonical)
        artifacts[filename]=digest(destination/filename)
        for kind in ['timing','area']:shutil.copy2(record[kind]['path'],destination/Path(record[kind]['path']).name)
    manifest={'version':'cooperate eleven effects + sparse dwell water','hardware_validation':'pending',
              'photo_format':'RGB565; RGB888 uses the existing slide path',
              'vertical_displacement_limit':6,'transition_steps':48,'max_dwell_drops':2,
              'files_sha256':artifacts,'boards':records,'effect_tests':validation,'subsystem_tests':regression}
    (destination/'validation.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Staged verified bitstreams: '+str(destination),flush=True)
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['a','b','stage']);ap.add_argument('--work',type=Path,default=WORK)
    ap.add_argument('--b-work',type=Path,default=Path('E:/Codex/Work/cooperate-fx11-water-20261018-r3'))
    ap.add_argument('--tests',type=Path,default=TESTS);ap.add_argument('--regressions',type=Path,default=TESTS/'subsystems')
    ap.add_argument('--mapped-from',type=Path);args=ap.parse_args()
    if args.action=='stage':stage(args.work.resolve(),args.b_work.resolve(),args.tests.resolve(),args.regressions.resolve())
    else:
        if args.action=='a':os.environ.setdefault('SAIXIAN_PLACE_SEED','19')
        if args.action=='a' and not os.environ.get('SAIXIAN_PHYSICAL_STRATEGY'):
            os.environ['SAIXIAN_PHYSICAL_STRATEGY']='MacroTiming'
        build(args.action,args.work.resolve(),args.mapped_from.resolve() if args.mapped_from else None)
