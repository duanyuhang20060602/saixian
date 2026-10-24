"""Build or stage the trophy-v5 pair with the eleven transitions preserved."""
from pathlib import Path
import argparse,hashlib,json,os,shutil
from build_v4_port import ROOT,build,digest,inputs
from test_award_v5 import JOBS as AWARD_JOBS
from test_fx11_water import SUITE
from test_v4_port import JOBS as SUBSYSTEM_JOBS
from verify_dlt import verify
from test_ip_optimization import JOBS as IP_JOBS
from ip_resource_audit import audit
def stage(a_work,b_work,award_tests,effect_tests,subsystems,eram_tests,ip_tests,menu_tests):
    records=[json.loads((w/f'builds/board_{b}/result.json').read_text()) for b,w in [('a',a_work),('b',b_work)]]
    groups=[]
    required=[(award_tests,set(AWARD_JOBS)),(effect_tests,set(SUITE)),
              (subsystems,set(SUBSYSTEM_JOBS)-{'tb_v4_transition_48','tb_v4_award_equivalence'}),
              (eram_tests,{'eram_contract','eram_vendor_model'}),(ip_tests,set(IP_JOBS)),(menu_tests,{'menu_palette'})]
    for directory,expected in required:
        results=json.loads((directory/'results.json').read_text())
        assert {r['test'] for r in results}==expected,'Incomplete verification: '+str(directory)
        for r in results:
            assert r['passed'] and r['inputs_unchanged'],r['test']
            assert all(digest(ROOT/p)==h for p,h in r['inputs_sha256'].items()),'Stale test '+r['test']
            assert all(digest(Path(p))==h for p,h in r.get('external_inputs_sha256',{}).items()),'Stale external reference'
            assert all(digest(directory/p)==h for p,h in r.get('stimuli_sha256',{}).items()),'Stale vectors'
            assert digest(directory/(r['test']+'.log'))==r['log_sha256'],'Changed test log '+r['test']
        groups.append(results)
    for r in records:
        assert r['status']=='passed' and r['inputs_sha256']==inputs('board_'+r['board']),'Stale or failed '+r['board']+' build'
        assert all(digest(Path(r[k]['path']))==r[k]['sha256'] for k in ['bit','timing','area'])
        assert all(digest(Path(p))==h for p,h in r['toolchain_sha256'].items()),'Changed toolchain'
    verify()
    resource_audit=audit(records,ip_tests.parent)
    destination=ROOT/'delivery/award_v5_fx11_ip_20261019';destination.mkdir(parents=True,exist_ok=False)
    artifacts={}
    for r in records:
        name='PHOTO_BOARD_'+r['board'].upper()+'_720P_AWARD_V5_FX11_IP.bit'
        shutil.copy2(r['bit']['path'],destination/name);artifacts[name]=digest(destination/name)
        canonical=ROOT/f'src/board_{r["board"]}/td_project'/('PHOTO_BOARD_'+r['board'].upper()+'.bit')
        shutil.copy2(r['bit']['path'],canonical)
        for kind in ['timing','area']:shutil.copy2(r[kind]['path'],destination/Path(r[kind]['path']).name)
    for name in ['AWARD720.DLT','AWARD720_DLT.json']:
        shutil.copy2(ROOT/'award_media'/name,destination/name);artifacts[name]=digest(destination/name)
    manifest={'version':'Accepted 3ac3c59 trophy visuals + lossless sparse 120-field lights + eleven transitions + dwell water',
              'hardware_validation':'pending','update_requires':['board A bitstream','board B bitstream','TF root AWARD720.DLT'],
              'reference_commit':'3ac3c59','files_sha256':artifacts,'boards':records,
              'award_tests':groups[0],'effect_tests':groups[1],'subsystem_tests':groups[2],
              'eram_delay_tests':groups[3],'ip_configuration_tests':groups[4],'menu_palette_tests':groups[5],
              'test_count':sum(map(len,groups)),'resource_audit':'ip_resource_comparison.json'}
    (destination/'validation.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    (destination/'ip_resource_comparison.json').write_text(json.dumps(resource_audit,indent=2)+'\n',encoding='utf-8')
    for directory,expected in required:
        log_dir=destination/'verification'/directory.parent.name/directory.name;log_dir.mkdir(parents=True,exist_ok=True)
        for name in expected:shutil.copy2(directory/(name+'.log'),log_dir/(name+'.log'))
        shutil.copy2(directory/'results.json',log_dir/'results.json')
    assert not any(p.suffix.lower() in ('.md','.zip') for p in destination.rglob('*'))
    print('Staged verified trophy-v5 delivery: '+str(destination))
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('action',choices=['a','b','stage']);ap.add_argument('--work',type=Path,required=True)
    ap.add_argument('--b-work',type=Path,default=Path('E:/Codex/Work/cooperate-ip-global/build-r4'))
    ap.add_argument('--award-tests',type=Path,default=Path('E:/Codex/Work/cooperate-award-v5-verified-tests'))
    ap.add_argument('--effects',type=Path,default=Path('E:/Codex/Work/cooperate-fx11-water-tests-20261018'))
    ap.add_argument('--subsystems',type=Path,default=Path('E:/Codex/Work/cooperate-award-v5-20261019/subsystems'))
    ap.add_argument('--eram-tests',type=Path,default=Path('E:/Codex/Work/cooperate-eram-delay/tests'))
    ap.add_argument('--ip-tests',type=Path,default=Path('E:/Codex/Work/cooperate-ip-global/tests'))
    ap.add_argument('--menu-tests',type=Path,default=Path('E:/Codex/Work/cooperate-ip-global/menu-tests'))
    ap.add_argument('--mapped-from',type=Path);ap.add_argument('--synthesis-strategy');ap.add_argument('--seed',type=int);a=ap.parse_args()
    if a.action=='stage':stage(a.work,a.b_work,a.award_tests,a.effects,a.subsystems,a.eram_tests,a.ip_tests,a.menu_tests)
    else:
        os.environ['SAIXIAN_PLACE_SEED']=str(a.seed if a.seed is not None else (17 if a.action=='a' else 24))
        os.environ.setdefault('SAIXIAN_PHYSICAL_STRATEGY','TimingUltraEmbedded' if a.action=='a' else 'MacroTimingExtra')
        if a.synthesis_strategy:os.environ['SAIXIAN_SYNTHESIS_STRATEGY']=a.synthesis_strategy
        build(a.action,a.work,a.mapped_from)
