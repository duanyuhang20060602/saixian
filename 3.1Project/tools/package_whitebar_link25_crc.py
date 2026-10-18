"""Package the matched 25 MHz / CRC board images with their build evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'delivery'
parser = argparse.ArgumentParser()
parser.add_argument('--variant', choices=['link25_crc', 'mem67_staged', 'group4_staged', 'av_b_winners', 'fluid_drop', 'fluid_select', 'fluid_priority', 'fluid_smooth', 'fluid_second', 'fluid_second6', 'av_refresh6'], default='link25_crc')
args = parser.parse_args()
TAG = args.variant if args.variant in ['av_b_winners', 'fluid_drop', 'fluid_select', 'fluid_priority', 'fluid_smooth', 'fluid_second', 'fluid_second6', 'av_refresh6'] else 'whitebar_' + args.variant
UPPER = TAG.upper()
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
files = [OUT / (UPPER + '_README.md')]
if args.variant in ['fluid_select', 'fluid_priority', 'fluid_smooth', 'fluid_second', 'fluid_second6', 'av_refresh6']:
    files += [ROOT / 'FLUID_PORTABILITY_20261018.md', OUT / (TAG + '_resource_comparison.json')]
boards = {}
for board in ['a', 'b']:
    report_path = OUT / f'board_{board}_v31_{TAG}.json'
    report = json.loads(report_path.read_text())
    bit = OUT / report['artifact']
    assert sha(bit) == report['sha256']
    assert all(sha(ROOT / path) == digest for path, digest in report['source_sha256'].items()), 'Source changed after build'
    assert report['timing_ns']['SWNS'] >= 0 and report['timing_ns']['HWNS'] >= 0
    assert report['timing_ns']['STNS'] == report['timing_ns']['HTNS'] == 0
    assert report['board_validation'] == 'pending'
    td = ROOT / f'projects/board_{board}/src/td_project'
    exception = OUT / f'board_{board}_{TAG}_exceptions.txt'
    shutil.copy2(td / f'PHOTO_BOARD_{board.upper()}_exception.timing', exception)
    files += [bit, report_path, exception]
    files += [OUT / f'board_{board}_{TAG}_{suffix}' for suffix in
              ['source_snapshot.json', 'build.log', 'timing.txt', 'area.txt']]
    boards[board.upper()] = {k: report[k] for k in ['artifact', 'sha256', 'timing_ns', 'resources', 'board_validation']}
manifest = OUT / (TAG + '_manifest.json')
manifest.write_text(json.dumps({'boards': boards, 'files_sha256': {p.name: sha(p) for p in files}}, indent=2) + '\n')
files.append(manifest)
archive = OUT / (UPPER + '_AB_20261018.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
    for path in files:
        package.write(path, path.name)
with zipfile.ZipFile(archive) as package:
    assert package.testzip() is None
    for path in files:
        assert hashlib.sha256(package.read(path.name)).hexdigest() == sha(path)
result = {'archive': archive.name, 'size_bytes': archive.stat().st_size, 'sha256': sha(archive), 'boards': boards}
(OUT / (TAG + '_package.json')).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
