"""Build an independent touchpad test image, require fresh reports and passing STA."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,time,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
TD=ROOT/'project';OUT=ROOT/'delivery';OUT.mkdir(exist_ok=True)
project=TD/'TOUCHPAD_SINGLE_TEST.al'
tree=ET.fromstring(project.read_text().replace('P&R','P&amp;R'))
tree.set('Path',TD.as_posix())
project.write_text(ET.tostring(tree,encoding='unicode').replace('P&amp;R','P&R'))
sources=list((ROOT/'rtl').rglob('*.v'))+list((ROOT/'constraints').glob('*'))+[project,TD/'build.tcl',TD/'sources.json']
def hashes():return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources)}
snapshot=hashes();start=time.time()
with (OUT/'build.log').open('w') as log:
 run=subprocess.run(['C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe','build.tcl'],cwd=TD,stdout=log,stderr=subprocess.STDOUT)
assert run.returncode==0,run.returncode
assert hashes()==snapshot,'Sources changed during build'
assert 'USR-8159 CRITICAL-WARNING' not in (OUT/'build.log').read_text(errors='replace')
timing=TD/'TOUCHPAD_SINGLE_TEST_pr.timing';bit=TD/'TOUCHPAD_SINGLE_TEST.bit'
assert timing.stat().st_mtime>=start and bit.stat().st_mtime>=start,'Stale artifact'
values={k:float(re.search(k+r':\s*([-\d.]+)ns',timing.read_text())[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
assert values['SWNS']>=0 and values['HWNS']>=0 and values['STNS']==values['HTNS']==0,values
target=OUT/'TOUCHPAD_SINGLE_BOARD_TEST.bit';shutil.copy2(bit,target)
area=TD/'TOUCHPAD_SINGLE_TEST_phy.area'
resources={k:int(re.search(r'^#'+k+r'\s+(\d+)',area.read_text(),re.M)[1]) for k in ['lut','reg','bram','bram32k','dsp']}
report=dict(artifact=target.name,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),timing_ns=values,resources=resources,source_sha256=snapshot,hardware_validation='pending',build_seconds=round(time.time()-start,1))
(OUT/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
shutil.copy2(timing,OUT/'timing.txt');shutil.copy2(area,OUT/'area.txt')
print(json.dumps({k:v for k,v in report.items() if k!='source_sha256'},indent=2),flush=True)
