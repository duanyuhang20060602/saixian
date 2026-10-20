from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'delivery'
report=json.loads((OUT/'build_report.json').read_text())
assert hashlib.sha256((OUT/report['artifact']).read_bytes()).hexdigest()==report['sha256']
for path,expected in report['source_sha256'].items():
 assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==expected,path
assert all(item['passed'] for item in json.loads((ROOT/'tests/results.json').read_text()))
files=[ROOT/'README.md',ROOT/'WIRING.md']
for folder in ['rtl','constraints','tools','hmi']:
 files.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.extend([ROOT/'project'/n for n in ['TOUCHPAD_SINGLE_TEST.al','build.tcl','sources.json']])
files.extend((ROOT/'tests').glob('*.v'))
files.extend(ROOT/'tests'/n for n in ['results.json','tb_single.log','tb_scene.log','preview.png'])
files.extend(OUT/n for n in ['TOUCHPAD_SINGLE_BOARD_TEST.bit','build_report.json','timing.txt','area.txt','build.log'])
manifest={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
manifest_path=OUT/'package_manifest.json';manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
files.append(manifest_path)
target=OUT/'TOUCHPAD_SINGLE_BOARD_TEST_SOURCE_AND_BIT.zip'
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(files):z.write(p,'touchpad-single-board-test/'+p.relative_to(ROOT).as_posix())
with zipfile.ZipFile(target) as z:assert z.testzip() is None
print(target.resolve());print(len(files),'files; build hashes verified')
