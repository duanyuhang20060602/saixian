"""Publish a locally verified integrated A/B pair, retaining parent firmware."""
from pathlib import Path
import argparse, datetime, json, shutil
from build_v4_port import ROOT, digest, inputs

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--work', type=Path, required=True)
    ap.add_argument('--validation', type=Path, required=True)
    ap.add_argument('--b-work', type=Path)
    args = ap.parse_args()
    suites = {
        'switch_timing': ROOT/'tests/switch_timing_results/results.json',
        'prefetch': ROOT/'tests/prefetch_overlap_results/results.json',
        'thumbnail': ROOT/'tests/thumbnail_early_results/results.json',
        'audio': args.validation/'audio_verified.json',
    }
    expected = {
        'switch_timing': {'tb_switch_timing','tb_switch_timing_control','tb_thumbnail_control'},
        'prefetch': {'compare','baseline_safety','early_safety'},
        'thumbnail': {'early','early_cancel','memory','overlay','phase','blanking','control','bandwidth565','timing_control'},
        'audio': {'model','native_model','volume','keys','transport','flow'},
    }
    tests = {}
    for suite, path in suites.items():
        records = read(path)
        assert {r['test'] for r in records} == expected[suite], suite
        for record in records:
            assert record['passed'], (suite, record['test'])
            for name, sha in record['inputs_sha256'].items():
                p = Path(name) if Path(name).is_absolute() else ROOT/name
                assert digest(p) == sha, ('Stale test', suite, name)
        tests[suite] = records
    boards = []
    for board in ('a','b'):
        work = args.b_work if board == 'b' and args.b_work else args.work
        record = read(work/f'builds/board_{board}/result.json')
        assert record['status'] == 'passed', board
        assert record['inputs_sha256'] == inputs('board_'+board), ('Stale build', board)
        for kind in ('bit','timing','area'):
            assert digest(Path(record[kind]['path'])) == record[kind]['sha256']
        boards.append(record)
    baseline = ROOT/'package_manifest.audio_baseline.json'
    assert not baseline.exists(), 'Use a fresh integration checkout for staging'
    shutil.copy2(ROOT/'package_manifest.json', baseline)
    manifest = read(baseline)
    manifest['historical_firmware'] = dict(manifest['release_files'])
    manifest['version'] = '5.4_MERGED'
    manifest['firmware_layout'] = 'canonical_with_history'
    manifest['saved_at'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    manifest['source_parents'] = [
        'b56f0afa5d40f9e9d69806118a93b16255d364b9',
        '7130c380f86acf23708a57273c79f5dbf849e2cb',
    ]
    manifest['source_release'] = 'releases/merged_20261023'
    manifest['change_scope'] = '5.4 audio pitch plus early thumbnail, overlapping prefetch and switch timing'
    manifest['hardware_validation'] = 'pending'
    manifest['release_files'] = {}
    manifest['release_builds'] = []
    destination = ROOT/manifest['source_release']
    destination.mkdir(parents=True, exist_ok=False)
    for record in boards:
        board = record['board']
        bit = ROOT/f'releases/PHOTO_BOARD_{board.upper()}_5_4_MERGED.bit'
        shutil.copy2(record['bit']['path'], bit)
        manifest['release_files'][bit.relative_to(ROOT).as_posix()] = digest(bit)
        for kind in ('timing','area'):
            shutil.copy2(record[kind]['path'], destination/Path(record[kind]['path']).name)
        record_path = destination/f'board_{board}_build.json'
        save(record_path, record)
        manifest['release_builds'].append({'board':board,'record':record_path.relative_to(ROOT).as_posix()})
    validation = {'hardware_validation':'pending','source_parents':manifest['source_parents'],
                  'boards':boards,'tests':tests,'test_count':sum(map(len,tests.values())),
                  'fresh_test_count':sum(r.get('verification_method')!='baseline_hash_reverification' for rs in tests.values() for r in rs),
                  'reverified_test_count':sum(r.get('verification_method')=='baseline_hash_reverification' for rs in tests.values() for r in rs),
                  'files_sha256':manifest['release_files']}
    save(ROOT/'integration_validation.json', validation)
    save(destination/'validation.json', validation)
    manifest['current_recorded_test_count'] = validation['test_count']
    manifest['previous_validation_note'] = 'Original records retained as history; current results in integration_validation.json.'
    manifest['saved_rtl_files'] = sum(1 for p in ROOT.rglob('*.v') if 'tests' not in p.parts)
    manifest['files_sha256'] = {
        p.relative_to(ROOT).as_posix():digest(p) for p in sorted(ROOT.rglob('*'))
        if p.is_file() and p.name != 'package_manifest.json'
        and '__pycache__' not in p.parts and p.suffix.lower() not in ('.vvp','.log','.logw','.pyc')
    }
    save(ROOT/'package_manifest.json', manifest)
    from verify_saved_project import verify
    assert verify()['passed']
    print('PASS merged package: '+str(ROOT)+'; '+str(validation['fresh_test_count'])+' fresh tests, '+str(validation['reverified_test_count'])+' reverified; both routed builds pass')

if __name__ == '__main__':
    main()
