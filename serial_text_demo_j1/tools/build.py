from pathlib import Path
import argparse,shutil,subprocess,re,json,hashlib
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--work',required=True,type=Path);a=ap.parse_args()
 fingerprint={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for d in ('rtl','vendor','td_project') for p in (ROOT/d).rglob('*') if p.is_file()}
 shutil.copytree(ROOT,a.work)
 td=a.work/'td_project';p=td/'TEXT_DEMO_J1.al';p.write_text(p.read_text(encoding='utf-8').replace((ROOT/'td_project').as_posix(),td.as_posix()),encoding='utf-8')
 with (a.work/'build.log').open('w') as f:r=subprocess.run(['C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe','build.tcl'],cwd=td,stdout=f,stderr=subprocess.STDOUT)
 timing=td/'TEXT_DEMO_J1_pr.timing';bit=td/'TEXT_DEMO_J1.bit';area=td/'TEXT_DEMO_J1_phy.area'
 vals={k:float(v) for k,v in re.findall(r'(SWNS|STNS|HWNS|HTNS):\s*(-?[0-9.]+)ns',timing.read_text())} if timing.exists() else {}
 assert r.returncode==0 and bit.exists() and len(vals)==4 and vals['SWNS']>=0 and vals['HWNS']>=0 and vals['STNS']==vals['HTNS']==0,(r.returncode,vals)
 out=ROOT/'releases';out.mkdir(exist_ok=True);shutil.copy2(bit,out/bit.name)
 for p in (timing,area):shutil.copy2(p,out/p.name)
 assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in fingerprint.items()),'Build inputs changed'
 (out/'build.json').write_text(json.dumps({'passed':True,'hardware_validation':'pending','base_commit':'585ea4008669ef5a350559405786b9b70be2afce','timing_ns':vals,'sha256':hashlib.sha256(bit.read_bytes()).hexdigest(),'inputs_sha256':fingerprint},indent=2),encoding='utf-8');print('PASS',vals)
if __name__=='__main__':main()
