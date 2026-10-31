from pathlib import Path
import subprocess,hashlib,json,re,os,time,argparse
ROOT=Path(__file__).resolve().parents[1];TD=ROOT/'project/src/td_project';USER=ROOT/'project/src/user_source'
parser=argparse.ArgumentParser();parser.add_argument('--seed',type=int,default=3);args=parser.parse_args()
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
# Make the Verilog include available to TD's project-relative reader as well.
(TD/'match_text.vh').write_bytes((USER/'hdl_source/match_text.vh').read_bytes())
inputs={str(p.relative_to(ROOT)).replace('\\','/'):digest(p) for p in USER.rglob('*') if p.is_file()}
for name in ['SAIXIAN_MATCH_SINGLE.al','build_match.tcl','key2_tf_flow.tcl','match_font.hex','match_text.vh']:
 inputs['project/src/td_project/'+name]=digest(TD/name)
env=os.environ.copy();env['SAIXIAN_TD_ROOT']='D:/TD';env['SAIXIAN_PLACE_SEED']=str(args.seed);env['SAIXIAN_START_STEP']='read_design'
tmp=ROOT/'results/tmp';tmp.mkdir(exist_ok=True);env['TEMP']=env['TMP']=str(tmp)
start=time.time();logpath=ROOT/f'results/build_seed{args.seed}.log'
record={'status':'failed','seed':args.seed,'source_hashes':inputs,'hardware_validation':'pending'}
with logpath.open('w',encoding='utf-8') as out:
 result=subprocess.run(['D:/TD/bin/td_commands_prompt.exe','build_match.tcl'],cwd=TD,env=env,stdout=out,stderr=subprocess.STDOUT)
log=logpath.read_text(encoding='utf-8',errors='replace')
try:
 assert result.returncode==0 and not re.search(r'(?m)^\S+ ERROR:',log),'TD build failed, inspect '+str(logpath)
 name='SAIXIAN_MATCH_SINGLE'
 for suffix in ['.bit','_pr.timing','_phy.area']:
  assert (TD/(name+suffix)).stat().st_mtime>=start-2,'Stale artifact '+suffix
 timing=(TD/(name+'_pr.timing')).read_text(errors='replace')
 slack={k:float(re.search(k+r':\s*([-\d.]+)ns',timing)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
 record['timing_ns']=slack
 assert slack['SWNS']>=0 and slack['HWNS']>=0 and slack['STNS']==0 and slack['HTNS']==0,'Routed timing failed'
 area=(TD/(name+'_phy.area')).read_text(errors='replace')
 usage={}
 for k in ['lut','reg','bram','bram32k','dsp']:
  m=re.search(r'(?m)^#'+k+r'\s+(\d+)\s+out of\s+(\d+)',area);assert m,k
  usage[k]={'used':int(m[1]),'total':int(m[2])};assert int(m[1])<=int(m[2])
 record['resources']=usage
 for path,sha in inputs.items():assert digest(ROOT/path)==sha,'Source changed '+path
 for suffix in ['.bit','_pr.timing','_phy.area']:
  source=TD/(name+suffix);target=ROOT/'delivery'/(('SAIXIAN_MATCH_SINGLE_20261026.bit') if suffix=='.bit' else name+suffix)
  target.write_bytes(source.read_bytes())
 record.update(status='passed',bit_sha256=digest(ROOT/'delivery/SAIXIAN_MATCH_SINGLE_20261026.bit'),seconds=round(time.time()-start,2))
 print(json.dumps({k:v for k,v in record.items() if k!='source_hashes'},indent=2),flush=True)
finally:
 (ROOT/f'results/build_seed{args.seed}.json').write_text(json.dumps(record,indent=2))
