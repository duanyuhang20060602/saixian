"""Build or stage a matched research-optimized pair with functional and physical checks."""
from pathlib import Path
import argparse,json,os,re,shutil
from build_v4_port import ROOT,build,digest,inputs
from test_award_v5 import JOBS as AWARD_JOBS
from test_fx11_water import SUITE
from test_v4_port import JOBS as SUBSYSTEM_JOBS
from test_ip_optimization import JOBS as IP_JOBS
from test_research_optimization import JOBS as RESEARCH_JOBS
from test_link_integration import JOBS as LINK_JOBS
from verify_dlt import verify

WORK=Path('E:/Codex/Work/cooperate-research-20261020')
SOURCES=[
 {'title':'Constant Multipliers for FPGAs','authors':'Florent de Dinechin; Vincent Lefevre','year':2000,
  'url':'https://www.researchgate.net/publication/221133996_Constant_Multipliers_for_FPGAs',
  'access':'Author-uploaded full text inspected; signed-digit shift/add/subtract principle adapted to three exact nine-bit menu products.'},
 {'title':'Algorithm for computer control of a digital plotter','author':'J. E. Bresenham','year':1965,'doi':'10.1147/SJ.41.0025',
  'url':'https://ibm-1401.info/Pics3/bresenham1965.pdf',
  'access':'Original paper inspected; incremental integer arithmetic adapted to the raster vertical scale, not copied as a line-drawing core.'},
 {'title':'Project F draw_line.sv','license':'MIT','commit':'dd212c2e5e0e0d8bdcf93ba077630dbfd49ae708',
  'url':'https://github.com/projf/projf-explore/blob/dd212c2e5e0e0d8bdcf93ba077630dbfd49ae708/lib/graphics/draw_line.sv',
  'access':'GitHub source inspected as an FPGA example of incremental raster arithmetic; no source copied into production.'},
 {'title':'verilog-axis axis_register.v','license':'MIT','commit':'48ff7a7e2ef782cf778d47910cf85835c64b1bce',
  'url':'https://github.com/alexforencich/verilog-axis/blob/48ff7a7e2ef782cf778d47910cf85835c64b1bce/rtl/axis_register.v',
  'access':'GitHub source inspected for elastic buffering and ready/valid backpressure. Implemented a protocol-specific one-word lookahead, not an AXI conversion. Repository is deprecated; no dependency introduced.'},
 {'title':'Parallel CRC Realization','authors':'Giuseppe Campobello; Giuseppe Patane; Marco Russo','year':2003,'doi':'10.1109/TC.2003.1234528',
  'url':'https://www.researchgate.net/publication/260750589_Parallel_crc_realization',
  'access':'IEEE endpoint unavailable; author-uploaded full text inspected. Linear-network and factoring prototypes tested, then rejected for lack of area benefit.'},
 {'title':'verilog-lfsr lfsr.v','license':'MIT','commit':'c1f86d036745935f3812ec6ddc7821c70ef4c9de',
  'url':'https://github.com/alexforencich/verilog-lfsr/blob/c1f86d036745935f3812ec6ddc7821c70ef4c9de/rtl/lfsr.v',
  'access':'GitHub mask/XOR implementation inspected. Existing serial-loop combinational CRC already maps to the same area; no dependency introduced.'}]

def mslices(record):
 log=(Path(record['work_project']).parent/'build.log').read_text(encoding='utf-8',errors='replace')
 values=re.findall(r'PHY-1001 : (\d+) mslices,',log)
 assert values,'Missing physical packing report'
 return int(values[-1])

def check_tests(directory,expected):
 records=json.loads((directory/'results.json').read_text())
 assert {r['test'] for r in records}==set(expected),'Incomplete tests: '+str(directory)
 for r in records:
  assert r['passed'] and r['inputs_unchanged'],r['test']
  assert all(digest(ROOT/p)==h for p,h in r['inputs_sha256'].items()),'Stale test: '+r['test']
  assert all(digest(Path(p))==h for p,h in r.get('external_inputs_sha256',{}).items()),'Stale reference'
  assert all(digest(directory/p)==h for p,h in r.get('stimuli_sha256',{}).items()),'Stale stimuli'
  assert digest(directory/(r['test']+'.log'))==r['log_sha256'],'Changed log: '+r['test']
 return records

def stage(a_work,b_work,destination):
 assert '.PREFETCH_WORD(1)' in (ROOT/'common/top_photo_b.v').read_text(), 'Production sender has no prefetch'
 top_a=(ROOT/'common/top_photo_a.v').read_text()
 assert '.SCALE_Y(1)' in top_a and 'ui_y<=raster_ui_y' in top_a, 'Production raster scale is not connected'
 groups={
  'award':(Path('E:/Codex/Work/cooperate-award-v5-verified-tests'),set(AWARD_JOBS)),
  'effects':(Path('E:/Codex/Work/cooperate-fx11-water-tests-20261018'),set(SUITE)),
  'subsystems':(Path('E:/Codex/Work/cooperate-award-v5-20261019/subsystems'),set(SUBSYSTEM_JOBS)-{'tb_v4_transition_48','tb_v4_award_equivalence'}),
  'eram':(Path('E:/Codex/Work/cooperate-eram-delay/tests'),{'eram_contract','eram_vendor_model'}),
  'ip':(Path('E:/Codex/Work/cooperate-ip-global/tests'),set(IP_JOBS)),
  'menu':(Path('E:/Codex/Work/cooperate-ip-global/menu-tests'),{'menu_palette'}),
  'research':(WORK/'tests',set(RESEARCH_JOBS)),
  'link_integration':(WORK/'integration-tests',set(LINK_JOBS))}
 tests={name:check_tests(directory,expected) for name,(directory,expected) in groups.items()}
 records=[json.loads((w/f'builds/board_{board}/result.json').read_text()) for board,w in [('a',a_work),('b',b_work)]]
 for r in records:
  assert r['status']=='passed' and r['inputs_sha256']==inputs('board_'+r['board']),'Stale/failed build'
  assert r['inputs_unchanged'] and r['toolchain_unchanged'] and r.get('mapped_origin_unchanged','mapped_origin' not in r)
  assert all(digest(Path(r[k]['path']))==r[k]['sha256'] for k in ('bit','timing','area')),'Changed output'
  assert all(digest(Path(p))==h for p,h in r['toolchain_sha256'].items()),'Changed toolchain'
  assert r['timing_ns']['SWNS']>=0 and r['timing_ns']['HWNS']>=0
  assert r['timing_ns']['STNS']==0 and r['timing_ns']['HTNS']==0
  assert mslices(r)<=4900
 verify()
 baselines=json.loads((WORK/'baselines.json').read_text())
 comparison={}
 allowed={'common/photo_link.v','common/photo_raster_delay.v','common/photo_settings_overlay.v','common/top_photo_a.v','common/top_photo_b.v'}
 for r in records:
  old=baselines[r['board']];assert old['status']=='passed'
  assert old['inputs_sha256'].keys()==r['inputs_sha256'].keys(),'Changed source/constraint list'
  changed=sorted(p for p,h in old['inputs_sha256'].items() if r['inputs_sha256'][p]!=h)
  assert set(changed)<=allowed,'Unrelated change or altered clock constraints: '+str(changed)
  comparison[r['board']]={'before':old['resources'],'after':r['resources'],
   'delta':{k:r['resources'][k]-v for k,v in old['resources'].items()},
   'before_mslices':mslices(old),'after_mslices':mslices(r),
   'before_timing_ns':old['timing_ns'],'after_timing_ns':r['timing_ns'],'changed_design_files':changed}
 constants=[{'value':v,'factor':k,'result':(v*k)&511} for v in range(32) for k in (28,72,112)]
 assert all(((v<<5)-(v<<2))&511==(28*v)&511 and ((v<<6)+(v<<3))&511==(72*v)&511 and
            ((v<<7)-(v<<4))&511==(112*v)&511 for v in range(32))
 assert all((683*y)>>10==(2*y)//3 for y in range(1024))
 report={'date':'2026-10-20','hardware_validation':'pending','sources':SOURCES,'boards':comparison,
  'baseline_records':{'sha256':digest(WORK/'baselines.json'),'records':baselines},
  'accepted':[
   {'method':'Signed-digit menu constants','files':['common/photo_settings_overlay.v'],
    'effect':'Exact nine-bit products 28*v,72*v,112*v. Standalone synthesis saves 8 LUT and 2 DSP; full-design results above.'},
   {'method':'Incremental integer raster scale','files':['common/photo_raster_delay.v','common/top_photo_a.v'],
    'effect':'Update floor(2*y/3) at line boundaries. Same startup, wrap, reset and registered output timing. Standalone trade: +16 LUT/+10 FF/-1 DSP.'},
   {'method':'One-word elastic link prefetch','files':['common/photo_link.v','common/top_photo_b.v'],
    'effect':'Read the next synchronous source word while transmitting the current word; retain it through stalls. Explicit frame/plane and abort guards.',
    'tradeoff':'Adds a small register buffer/control on B; link remains 25 MHz with falling-edge output launch and rising-edge consumption. No FIFO depth or precision reduced.'}],
  'rejected':[{'method':'Parallel CRC matrix, folded input and greedy XOR common-subexpression factoring',
   'reason':'Existing compiler already maps the CRC compactly: baseline/matrix/fold each 69 LUT, greedy factoring 72 LUT. No production CRC change.',
   'equivalence_log':(WORK/'crc/equivalence.log').read_text(),
   'synthesis':json.loads((WORK/'crc/results.json').read_text())},
   {'method':'Move every real-time rendered frame from A to B',
    'reason':'Keep B preprocessing/FFT and A real-time rendering. The existing 16-bit 25 MHz link has a 50 MB/s raw upper bound; the current receive word bubble limits payload to 33.33 MB/s after prefetch. Uncompressed 720p RGB565 at the current 75 MHz, 1650x750 raster needs about 111.71 MB/s. Moving all per-frame rendering requires a different transport or compression, not only a task reassignment.',
    'evidence_type':'Bandwidth calculation from current local RTL and constraints; architectural inference, not hardware measurement.'}],
  'micro_synthesis':{'menu':json.loads((WORK/'csd/area_comparison.json').read_text()),
                     'raster':json.loads((WORK/'raster/area_comparison.json').read_text())},
  'micro_synthesis_limit':'Isolated savings do not add across the whole design. The baseline full-design menu hierarchy already used zero DSP after constant propagation; the final physical board totals, not the isolated menu DSP count, determine the net gain.',
  'exhaustive_arithmetic':{'menu_cases':constants,'raster_y_values':1024},
  'transfer_measurements':{r['test']:r['measurements'] for r in tests['research'] if 'measurements' in r},
  'link_stage_summary':[
    {'test':r['test'],'before_cycles':m[0]['cycles'],'after_cycles':m[1]['cycles'],
     'before_ms_at_25MHz':m[0]['cycles']/25000,'after_ms_at_25MHz':m[1]['cycles']/25000,
     'duration_reduction_percent':100*(1-m[1]['cycles']/m[0]['cycles'])}
    for r in tests['research'] if 'measurements' in r
    for m in [sorted(r['measurements'],key=lambda x:x['prefetch'])]],
  'limits':'Measured link-stage simulations, not whole SD-to-screen latency or hardware results. No global optimality claim.',
  'physical_trials':[{'result':str(p),'board':t['board'],'status':t['status'],'resources':t.get('resources'),
                      'timing_ns':t.get('timing_ns'),'seed':t.get('place_seed_override'),
                      'strategy':t.get('physical_strategy',{}).get('name'),'termination_reason':t.get('termination_reason')}
                     for p in sorted(WORK.glob('build-r*/builds/board_*/result.json'))
                     for t in [json.loads(p.read_text())]],
  'rebuild_commands':{
    r['board']:['python','-B','tools/build_research_optimization.py',r['board'],
                '--work','E:/Codex/Work/cooperate-research-20261020/rebuild',
                '--seed',r['place_seed_override'],'--physical-strategy',r['physical_strategy']['name']]
    for r in records},
  'preserved':'Full trophy-v5 visuals/media, eleven transitions and dwell water, RGB565/RGB888 precision, audio, CRC and SOF/EOF checks, clock constraints and FIFO capacities.'}
 # Check every dependency first, then create a new delivery. Never replace an older delivery.
 destination.mkdir(parents=True,exist_ok=False);artifacts={}
 for r in records:
  name='PHOTO_BOARD_'+r['board'].upper()+'_720P_RESEARCH_20261020.bit'
  shutil.copy2(r['bit']['path'],destination/name);artifacts[name]=digest(destination/name)
  for kind in ('timing','area'):shutil.copy2(r[kind]['path'],destination/Path(r[kind]['path']).name)
 for name in ('AWARD720.DLT','AWARD720_DLT.json'):
  shutil.copy2(ROOT/'award_media'/name,destination/name);artifacts[name]=digest(destination/name)
 for name,(directory,_) in groups.items():
  target=destination/'verification'/name;target.mkdir(parents=True)
  for r in tests[name]:shutil.copy2(directory/(r['test']+'.log'),target/(r['test']+'.log'))
  shutil.copy2(directory/'results.json',target/'results.json')
 manifest={'version':'Trophy-v5 + eleven transitions/dwell water + exact arithmetic and elastic link optimization',
  'hardware_validation':'pending','files_sha256':artifacts,'boards':records,'tests':tests,
  'test_count':sum(map(len,tests.values())),'research_report':'research_results.json',
  'TF_media':'AWARD720.DLT is byte-identical to the preceding trophy-v5 delivery; an already installed matching file can be retained.'}
 (destination/'validation.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
 (destination/'research_results.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 assert not any(p.suffix.lower() in ('.md','.zip') for p in destination.rglob('*'))
 for r in records:
  canonical=ROOT/f'src/board_{r["board"]}/td_project'/('PHOTO_BOARD_'+r['board'].upper()+'.bit')
  shutil.copy2(r['bit']['path'],canonical)
 print(json.dumps({'delivery':str(destination),'test_count':manifest['test_count'],'boards':comparison},indent=2),flush=True)

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('action',nargs='?',choices=['a','b','stage'],default='stage')
 ap.add_argument('--a-work',type=Path,default=WORK/'build-r4');ap.add_argument('--b-work',type=Path,default=WORK/'build-r4')
 ap.add_argument('--destination',type=Path,default=ROOT/'delivery/research_20261020')
 ap.add_argument('--work',type=Path,default=WORK/'rebuild');ap.add_argument('--mapped-from',type=Path)
 ap.add_argument('--seed',type=int,default=24);ap.add_argument('--physical-strategy',default='TimingUltraEmbedded');a=ap.parse_args()
 if a.action=='stage':stage(a.a_work,a.b_work,a.destination)
 else:
  os.environ['SAIXIAN_PLACE_SEED']=str(a.seed);os.environ['SAIXIAN_PHYSICAL_STRATEGY']=a.physical_strategy
  build(a.action,a.work,a.mapped_from)
