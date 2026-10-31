from pathlib import Path
import json,hashlib,shutil
ROOT=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
build=json.loads((ROOT/'results/build_seed3.json').read_text())
assert build['status']=='passed'
for relative,sha in build['source_hashes'].items():assert digest(ROOT/relative)==sha,relative
tests=json.loads((ROOT/'results/tests.json').read_text());assert len(tests)==5 and all(t['passed'] for t in tests)
bit=ROOT/'delivery/SAIXIAN_MATCH_SINGLE_20261026.bit';assert digest(bit)==build['bit_sha256']
shutil.copyfile(ROOT/'使用说明.md',ROOT/'delivery/使用说明.md')
shutil.copyfile(ROOT/'results/rtl_preview.png',ROOT/'delivery/RTL画面预览.png')
test_records=[]
for t in tests:
 name=t['test'];log=ROOT/f'results/tests/{name}.log';s=log.read_text()
 assert 'PASS' in s and 'FATAL' not in s
 sources=[ROOT/f'tests/tb_match_{name}.v']
 assert all(p.is_file() for p in sources)
 test_records.append({**t,'log_sha256':digest(log),'testbench_sha256':digest(sources[0])})
out={'product':'赛显单板赛事计分演示','date':'2026-10-26','device':'EG4S20BG256','hardware_validation':'pending',
 'board_connection':'One HX4S20C board, HDMI_A; no TF card or serial touchscreen required',
 'build':{k:v for k,v in build.items() if k!='source_hashes'},'source_hashes':build['source_hashes'],
 'tests':test_records,'preview':'RTL simulation, not a hardware capture',
 'dual_board_integration':'not implemented; wait for single-board acceptance',
 'delivery_sha256':{p.name:digest(p) for p in (ROOT/'delivery').iterdir() if p.is_file() and p.name!='manifest.json'}}
(ROOT/'delivery/manifest.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':True,'bit':str(bit),'sha256':digest(bit),'tests':len(tests)},indent=2))
