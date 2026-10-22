"""Stage a fresh A/B spotlight fix only after current proofs and timing pass."""
from pathlib import Path
import argparse,json,shutil
from build_v4_port import ROOT,digest,inputs
from build_research_optimization import check_tests,mslices
from test_award_v5 import JOBS as AWARD
from test_fx11_water import SUITE
from test_v4_port import JOBS as SUBSYSTEMS
from test_ip_optimization import JOBS as IP
from test_research_optimization import JOBS as RESEARCH
from test_link_integration import JOBS as LINK
from verify_dlt import verify
WORK=Path('E:/Codex/Work/cooperate-spotlight-fix-20261020')
BASE=Path('E:/Codex/Work/cooperate-research-20261020/build-r4')
def validate_record(record,directory):
    assert record['passed'] and record['inputs_unchanged'],record['test']
    assert all(digest(ROOT/p)==h for p,h in record['inputs_sha256'].items()),'Stale '+record['test']
    assert all(digest(Path(p))==h for p,h in record.get('external_inputs_sha256',{}).items())
    assert all(digest(directory/p)==h for p,h in record.get('stimuli_sha256',{}).items())
    assert all(digest(directory/p)==h for p,h in record.get('derived_sha256',{}).items())
    assert digest(directory/(record['test']+'.log'))==record['log_sha256']
def stage(a_work,b_work,destination):
    groups={
      'award':(Path('E:/Codex/Work/cooperate-award-v5-verified-tests'),set(AWARD)),
      'effects':(Path('E:/Codex/Work/cooperate-fx11-water-tests-20261018'),set(SUITE)),
      'subsystems':(Path('E:/Codex/Work/cooperate-award-v5-20261019/subsystems'),set(SUBSYSTEMS)-{'tb_v4_transition_48','tb_v4_award_equivalence'}),
      'eram':(Path('E:/Codex/Work/cooperate-eram-delay/tests'),{'eram_contract','eram_vendor_model'}),
      'ip':(Path('E:/Codex/Work/cooperate-ip-global/tests'),set(IP)),
      'menu':(Path('E:/Codex/Work/cooperate-ip-global/menu-tests'),{'menu_palette'}),
      'research':(Path('E:/Codex/Work/cooperate-research-20261020/tests'),set(RESEARCH)),
      'integration':(Path('E:/Codex/Work/cooperate-research-20261020/integration-tests'),set(LINK))}
    tests={name:check_tests(directory,expected) for name,(directory,expected) in groups.items()}
    extra=[]
    for directory,expected in [(WORK/'transport-tests-r3',{'original_corruption','sdram_link_565','sdram_link_888'}),
                               (WORK/'tests',{'native_midframe'})]:
        selected=[r for r in json.loads((directory/'results.json').read_text()) if r['test'] in expected]
        assert {r['test'] for r in selected}==expected
        for r in selected:validate_record(r,directory);extra.append((r,directory))
    tests['spotlights']=[r for r,_ in extra]
    assert sum(map(len,tests.values()))==65
    records=[json.loads((w/f'builds/board_{b}/result.json').read_text()) for b,w in [('a',a_work),('b',b_work)]]
    comparison={};allowed={'common/top_photo_a.v','common/photo_award_render.v','src/board_b/user_source/hdl_source/frame_store.v'}
    for r in records:
        assert r['status']=='passed' and r['inputs_unchanged'] and r['toolchain_unchanged']
        assert r.get('mapped_origin_unchanged','mapped_origin' not in r)
        assert r['inputs_sha256']==inputs('board_'+r['board'])
        assert all(digest(Path(r[k]['path']))==r[k]['sha256'] for k in ('bit','timing','area'))
        assert all(digest(Path(p))==h for p,h in r['toolchain_sha256'].items())
        assert r['timing_ns']['SWNS']>=0 and r['timing_ns']['HWNS']>=0 and r['timing_ns']['STNS']==r['timing_ns']['HTNS']==0
        assert mslices(r)<=4900
        old=json.loads((BASE/f'builds/board_{r["board"]}/result.json').read_text())
        assert old['inputs_sha256'].keys()==r['inputs_sha256'].keys()
        changed=[p for p,h in old['inputs_sha256'].items() if r['inputs_sha256'][p]!=h]
        assert set(changed)<=allowed,changed
        comparison[r['board']]={'changed_design_files':changed,'resources':r['resources'],
                               'resource_delta':{p:v-old['resources'][p] for p,v in r['resources'].items()},
                               'mslices':mslices(r),'timing_ns':r['timing_ns']}
    verify();destination.mkdir(parents=True,exist_ok=False);artifacts={}
    for r in records:
        name='PHOTO_BOARD_'+r['board'].upper()+'_720P_SPOTLIGHT_FIX_20261020.bit'
        shutil.copy2(r['bit']['path'],destination/name);artifacts[name]=digest(destination/name)
        for k in ('area','timing'):shutil.copy2(r[k]['path'],destination/Path(r[k]['path']).name)
    for name in ('AWARD720.DLT','AWARD720_DLT.json'):
        shutil.copy2(ROOT/'award_media'/name,destination/name);artifacts[name]=digest(destination/name)
    for group,(directory,_) in groups.items():
        target=destination/'verification'/group;target.mkdir(parents=True)
        for r in tests[group]:shutil.copy2(directory/(r['test']+'.log'),target/(r['test']+'.log'))
        (target/'results.json').write_text(json.dumps(tests[group],indent=2)+'\n',encoding='utf-8')
    target=destination/'verification/spotlights';target.mkdir(parents=True)
    for r,directory in extra:shutil.copy2(directory/(r['test']+'.log'),target/(r['test']+'.log'))
    (target/'results.json').write_text(json.dumps(tests['spotlights'],indent=2)+'\n',encoding='utf-8')
    card=Path('F:/AWARD720.DLT')
    manifest={'version':'B award SDRAM alignment and A live spotlight diagnostic',
      'hardware_validation':'pending','test_count':65,'files_sha256':artifacts,'boards':records,
      'comparison':comparison,'tests':tests,
      'diagnosis':{'reproduced_contract':'Existing read calibration: raw SDRAM data leads valid by one memory clock.',
                   'before':'B award reads bypassed the capture register. Shifted light pointers/bitmaps can pass link CRC because corruption precedes CRC generation.',
                   'after':'B applies its existing capture register to award words in both color settings. A exposes light error and field counter.',
                   'scope_limit':'Simulation reproduction and placed/routed timing are verified; physical-board confirmation is still required.'},
      'A_display':{'format':'46EFFC','E':'hex light error: 0 OK, 2 pointer, 3 bitmap, 4 decoder FSM, 7 missing row deadline',
                   'FF':'hex spotlight field 00..77, advances every three display frames; KEY2 pauses/resumes',
                   'priority':'Earlier transfer/startup faults retain priority over live spotlight status.'},
      'TF_media':{'changed':False,'sha256':artifacts['AWARD720.DLT'],
                  'card_present':card.exists(),'card_sha256':digest(card) if card.exists() else None},
      'programming':'Program the named bitstream into its corresponding A/B board. PROGRAM_SRAM must be repeated after a power cycle.',
      'preserved':'Trophy pixels and 120 lossless light fields, eleven transitions/dwell water, audio, RGB precision, CRC/markers, all clocks and FIFO depths.'}
    (destination/'validation.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    assert not any(p.suffix.lower() in ('.md','.zip') for p in destination.rglob('*'))
    for r in records:
        canonical=ROOT/f'src/board_{r["board"]}/td_project'/('PHOTO_BOARD_'+r['board'].upper()+'.bit')
        shutil.copy2(r['bit']['path'],canonical);assert digest(canonical)==r['bit']['sha256']
    print(json.dumps({'delivery':str(destination),'tests':65,'boards':comparison},indent=2))
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--a-work',type=Path,default=WORK/'build-r1')
    ap.add_argument('--b-work',type=Path,default=WORK/'build-r2')
    ap.add_argument('--destination',type=Path,default=ROOT/'delivery/spotlight_fix_20261020');a=ap.parse_args()
    stage(a.a_work,a.b_work,a.destination)
