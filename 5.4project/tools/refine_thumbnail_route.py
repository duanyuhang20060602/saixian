"""Incrementally refine a fingerprint-checked routed checkpoint, retaining clocks."""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,shutil,subprocess,time
from build_v4_port import ROOT,inputs

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,v):Path(p).write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8')
def refine(source,work,rounds=8):
    origin_file=source/'builds/board_a/result.json'
    origin=json.loads(origin_file.read_text(encoding='utf-8'))
    assert origin['inputs_unchanged'] and origin['toolchain_unchanged']
    before=inputs('board_a');assert origin['inputs_sha256']==before
    assert all(sha(p)==h for p,h in origin['toolchain_sha256'].items())
    original=Path(origin['work_project']);relative=Path('src/board_a/td_project')
    db=original/relative/'PHOTO_BOARD_A_pr.db';db_hash=sha(db)
    out=work/'builds/board_a';project=out/'project'
    assert not project.exists()
    shutil.copytree(original,project,ignore=shutil.ignore_patterns('*.bit','*.log','*.logw','*_Runs'))
    td=project/relative;name='PHOTO_BOARD_A';al=td/(name+'.al')
    text=al.read_text(encoding='utf-8-sig')
    text,count=re.subn(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+td.as_posix()+m[2],text,count=1)
    assert count==1;al.write_text(text,encoding='utf-8',newline='\n')
    script=f'''import_device eagle_s20.db -package EG4S20BG256
open_project {{{name}.al}} -single_run
import_db {{{name}_pr.db}}
set_param route post_route_opt high
set_param route postrt_opt_extra_round {rounds}
set_param route fix_hold off
route -incremental
fix_hold
set_param route fix_hold on
update_timing -mode final
report_area -io_info -file {{{name}_phy.area}}
report_timing_status -file {{{name}_phy.ts}}
report_timing_summary -file {{{name}_pr.timing}}
export_db {{{name}_refined.db}}
bitgen -bit {{{name}.bit}}
close_project
exit
'''
    flow=td/'refine_route.tcl';flow.write_text(script,encoding='utf-8',newline='\n')
    record={'board':'a','status':'running','hardware_validation':'pending','work_project':str(project),
            'inputs_sha256':before,'toolchain_sha256':origin['toolchain_sha256'],
            'routed_origin':{'result':str(origin_file),'result_sha256':sha(origin_file),'checkpoint':str(db),'checkpoint_sha256':db_hash},
            'refinement':{'mode':'route -incremental','postrt_opt_extra_round':rounds,'script_sha256':sha(flow)},
            'place_seed_override':origin.get('place_seed_override'),'physical_strategy':origin.get('physical_strategy')}
    write(out/'result.json',record)
    env=os.environ.copy();temp=Path('E:/Codex/Temp/thumbnail-5.0');temp.mkdir(parents=True,exist_ok=True)
    env.update(TEMP=str(temp),TMP=str(temp));tool=next(Path(p) for p in origin['toolchain_sha256'] if p.endswith('td_commands_prompt.exe'))
    started=time.time()
    with (out/'build.log').open('w',encoding='utf-8') as log:
        run=subprocess.run([str(tool),flow.name],cwd=td,env=env,stdout=log,stderr=subprocess.STDOUT)
    record.update(returncode=run.returncode,seconds=round(time.time()-started,1),
                  inputs_unchanged=before==inputs('board_a'),
                  toolchain_unchanged=all(sha(p)==h for p,h in origin['toolchain_sha256'].items()),
                  routed_origin_unchanged=sha(db)==db_hash)
    area=td/(name+'_phy.area');timing=td/(name+'_pr.timing');bit=td/(name+'.bit')
    area_text=area.read_text(errors='replace') if area.exists() else ''
    timing_text=timing.read_text(errors='replace') if timing.exists() else ''
    usage={k:int(v) for k,v in re.findall(r'(?m)^\s*#(lut|reg|bram|bram32k|dsp)\s+(\d+)\b',area_text)}
    times={k:float(v) for k,v in re.findall(r'(SWNS|STNS|HWNS|HTNS):\s*(-?[0-9.]+)ns',timing_text)}
    record.update(resources=usage,timing_ns=times)
    fresh=all(p.is_file() and p.stat().st_mtime>=started for p in (area,timing,bit))
    log=(out/'build.log').read_text(errors='replace')
    passed=run.returncode==0 and fresh and not re.search(r'(?im)^.*(?:ERROR:|ERROR \[)',log)
    passed=passed and record['inputs_unchanged'] and record['toolchain_unchanged'] and record['routed_origin_unchanged']
    passed=passed and len(times)==4 and times['SWNS']>=0 and times['HWNS']>=0 and times['STNS']==0 and times['HTNS']==0
    for kind,p in [('area',area),('timing',timing),('bit',bit)]:
        if p.exists():record[kind]={'path':str(p),'sha256':sha(p)}
    record['status']='passed' if passed else 'failed';write(out/'result.json',record)
    print(json.dumps({k:record[k] for k in ('status','resources','timing_ns','seconds')},indent=2),flush=True)
    if not passed:raise SystemExit(1)
    return record

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--from-build',type=Path,required=True)
    ap.add_argument('--work',type=Path,required=True);ap.add_argument('--rounds',type=int,default=8)
    args=ap.parse_args();refine(args.from_build,args.work,args.rounds)
