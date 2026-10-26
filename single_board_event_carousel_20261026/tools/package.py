from pathlib import Path
import json,hashlib,shutil,re
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
build=json.loads((ROOT/'results/build_seed3.json').read_text());assert build['status']=='passed'
for relative,sha in build['source_hashes'].items():assert digest(ROOT/relative)==sha,relative
tests=json.loads((ROOT/'results/tests.json').read_text());assert len(tests)==7 and all(t['passed'] for t in tests)
reference=json.loads((ROOT/'results/pipeline_reference.json').read_text())
for name,sha in reference.items():assert hashlib.sha256(Image.open(ROOT/f'results/tests/{name}.png').tobytes()).hexdigest()==sha,'Pipeline changed pixels: '+name
bit=ROOT/'delivery/SAIXIAN_EVENT_CAROUSEL_SINGLE_20261026.bit';assert digest(bit)==build['bit_sha256']
# Verify the independently encoded MIFs match the simulation HEXs, so the
# actual native RAM initialization agrees with the indexed-pixel test.
for i in range(9):
 p=ROOT/f'project/src/td_project/trophy_{i}.mif';entries=re.findall(r'(?m)^([0-9A-F]+) : ([0-9A-F]+);',p.read_text())
 values=[int(v,16) for a,v in entries];assert [int(a,16) for a,v in entries]==list(range(2048))
 assert values==[int(v,16) for v in (p.with_suffix('.hex')).read_text().split()]
shutil.copyfile(ROOT/'组合方案与使用说明.md',ROOT/'delivery/组合方案与使用说明.md')
shutil.copyfile(ROOT/'results/rtl_preview.png',ROOT/'delivery/RTL画面预览.png')
shutil.copyfile(ROOT/'results/tests/home.png',ROOT/'delivery/赛事首页.png')
shutil.copyfile(ROOT/'results/tests/winner_a.png',ROOT/'delivery/赛后颁奖.png')
records=[]
for t in tests:
 name=t['test'];log=ROOT/f'results/tests/{name}.txt';text=log.read_text();assert 'PASS' in text and 'FATAL' not in text
 top='tb_event_'+name if name in ['flow','trophy'] else 'tb_match_'+name
 records.append({**t,'log_sha256':digest(log),'testbench_sha256':digest(ROOT/f'tests/{top}.v')})
out={'product':'赛显单板：赛事轮播、比分与原工程奖杯组合版','date':'2026-10-26','device':'EG4S20BG256',
 'hardware_validation':'pending user acceptance','scope':'Built-in event pages, shared match state and result, original trophy derivative ROM; HDMI_A; no TF image filters',
 'build':{k:v for k,v in build.items() if k!='source_hashes'},'source_hashes':build['source_hashes'],'tests':records,
 'pipeline_pixel_equivalence':{'passed':True,'unchanged_scenes':list(reference),'summary_header':'Intentionally changed from award title to results title'},
 'trophy_source':json.loads((ROOT/'results/trophy_source.json').read_text()),
 'dual_board_code':'unchanged; integration plan in the usage document',
 'delivery_sha256':{p.name:digest(p) for p in (ROOT/'delivery').iterdir() if p.is_file() and p.name!='manifest.json'}}
(ROOT/'delivery/manifest.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':True,'bit':str(bit),'sha256':digest(bit),'tests':len(tests)},indent=2))
