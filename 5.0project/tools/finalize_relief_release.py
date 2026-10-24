"""Publish the two current 5.0 images only after build/test fingerprints match."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, shutil
from build_v4_port import ROOT, inputs
from verify_saved_project import verify
from test_relief_controls import JOBS as CONTROL_TESTS
from test_relief_bus import JOBS as DISPLAY_TESTS

_before = {}


def remember(p):
    p = p.resolve()
    assert p.is_relative_to(ROOT), 'Publication must stay inside the active project'
    if p not in _before:
        _before[p] = p.read_bytes() if p.is_file() else None


def copy(source, destination):
    remember(destination)
    shutil.copy2(source, destination)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def read(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def write(p, value):
    remember(p)
    p.write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


def fingerprints_match(record):
    values = record.get('inputs_sha256', {})
    if not values or not record.get('passed'):
        return False
    for relative, digest in values.items():
        p = Path(relative)
        p = p if p.is_absolute() else ROOT/p
        if not p.is_file() or sha(p) != digest:
            return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--work', type=Path, required=True)
    ap.add_argument('--a', type=Path, required=True)
    ap.add_argument('--b', type=Path, required=True)
    ap.add_argument('--tests', type=Path, nargs='+', required=True)
    args = ap.parse_args()
    manifest = read(ROOT/'package_manifest.json')
    assert manifest['version'] == '5.0'
    verify(strict=False)
    assert not any(p.suffix.lower() in ('.md', '.zip') for p in ROOT.rglob('*') if p.is_file())
    assert {p.resolve() for p in ROOT.rglob('*.bit')} == {(ROOT/p).resolve() for p in manifest['release_files']}
    boards = []
    for board, base in [('a', args.a), ('b', args.b)]:
        record = read(base/f'builds/board_{board}/result.json')
        assert record['board'] == board and record['status'] == 'passed'
        assert record['inputs_sha256'] == inputs('board_'+board), 'Changed build inputs'
        assert record['inputs_unchanged'] and record['toolchain_unchanged']
        if record.get('local_flow'):
            assert record['local_flow_unchanged']
            assert sha(Path(record['local_flow']['path'])) == record['local_flow']['sha256']
        for kind in ['bit', 'timing', 'area']:
            assert sha(Path(record[kind]['path'])) == record[kind]['sha256']
        log = base/f'builds/board_{board}/build.log'
        slices = re.findall(r'PHY-1001 : (\d+) mslices,', log.read_text(errors='replace'))
        assert slices and int(slices[-1]) <= 4900
        record['physical_mslices'] = int(slices[-1])
        boards.append((record, log))
    asset = args.work/'media/RELIEF720.DLT'
    assert sha(asset) == read(asset.with_suffix('.json'))['sha256']
    fresh = []
    for report in args.tests:
        values = read(report)
        assert isinstance(values, list) and values
        for record in values:
            assert fingerprints_match(record), 'Stale or failed test: '+str(report)+' '+record['test']
            if 'asset_sha256' in record:
                assert record['asset_sha256'] == sha(asset)
            log = Path(record.get('log', report.parent/(record['test']+'.log')))
            assert log.is_file() and sha(log) == record['log_sha256'], str(log)
            fresh.append((record, log, report.parent.name))
    required = set(CONTROL_TESTS) | set(DISPLAY_TESTS) | {'render_cdc','native_materials','native_link','native_slots','native_cache','touch'}
    if 'module photo_relief_product' in (ROOT/'common/photo_relief_player.v').read_text(encoding='utf-8'):
        required |= {'product_native', 'player_native', 'bus_native'}
    if 'result_select_blue_q' in (ROOT/'common/top_photo_a.v').read_text(encoding='utf-8'):
        required.add('result_controls')
    if 'session_match_q' in (ROOT/'common/photo_cached_control_a.v').read_text(encoding='utf-8'):
        required.add('uart_contract')
    if re.search(r'function\s+\[[^\]]+\]\s+phase_curve\b', (ROOT/'common/award_fx.v').read_text(encoding='utf-8')):
        required.add('legacy_wave_exact')
    if 'shared_award_cache' in (ROOT/'common/photo_award_render.v').read_text(encoding='utf-8'):
        required |= {'shared_cache', 'shared_legacy_rows'}
    if 'RELIEF_TIMER_PIPELINE' in (ROOT/'common/photo_cached_control_a.v').read_text(encoding='utf-8'):
        required.add('timer_equivalence')
    if 'DISPLAY_CONTROL_STAGE' in (ROOT/'common/top_photo_a.v').read_text(encoding='utf-8'):
        required.add('display_controls')
    assert required <= {r['test'] for r, _, _ in fresh}, 'Missing required relief regressions'
    destination = ROOT/'releases/relief_native_20261024'
    destination.mkdir(parents=True, exist_ok=True)
    logs = destination/'validation'
    logs.mkdir(exist_ok=True)
    tests = []
    for record, log, suite in fresh:
        r = dict(record, suite=suite, reexecuted=record.get('reexecuted',True))
        saved = logs/(suite+'_'+record['test']+'.log')
        copy(log, saved)
        r['saved_log'] = saved.relative_to(ROOT).as_posix()
        tests.append(r)
    prior = read(ROOT/'releases/relief_hq_20261024/validation.json')
    unchanged, historical = [], []
    test_key=lambda r:(r['test'],json.dumps(r['inputs_sha256'],sort_keys=True))
    seen={test_key(r) for r in tests}
    for record in prior['tests']:
        if fingerprints_match(record):
            key=test_key(record)
            if key not in seen:
                unchanged.append(dict(record, reexecuted=False, unchanged_reverified=True));seen.add(key)
        else:
            historical.append({'test': record['test'], 'suite': record.get('suite'),
                               'reason': 'Historical input hashes no longer match current project; excluded from current pass count.'})
    executed_count=sum(bool(r.get('reexecuted')) for r in tests)
    verified_count=len(tests)+len(unchanged)-executed_count
    releases = {}
    release_builds = []
    for record, log in boards:
        name = 'PHOTO_BOARD_'+record['board'].upper()
        saved = ROOT/'releases'/(name+'_5_0.bit')
        copy(record['bit']['path'], saved)
        releases[saved.relative_to(ROOT).as_posix()] = sha(saved)
        record_path = destination/('board_'+record['board']+'_build.json')
        write(record_path, record)
        copy(log, destination/('board_'+record['board']+'_build.log'))
        for kind in ['area', 'timing']:
            source = Path(record[kind]['path'])
            copy(source, ROOT/'releases'/source.name)
            copy(source, destination/source.name)
        release_builds.append({k: record[k] for k in ['board', 'resources', 'timing_ns', 'physical_mslices']}
                              | {'bit_sha256': record['bit']['sha256'], 'record': record_path.relative_to(ROOT).as_posix()})
    for folder in [ROOT/'award_media', ROOT/'examples/TF卡素材', ROOT/'releases']:
        copy(asset, folder/'RELIEF720.DLT')
    for folder in [ROOT/'award_media', ROOT/'releases']:
        copy(asset.with_suffix('.json'), folder/'RELIEF720_DLT.json')
    preview = args.work/'preview/rtl_reference_0.png'
    if preview.is_file():
        copy(preview, destination/'rtl_reference_0.png')
    for name in ['cup_body_comparison.png','cup_light_comparison.png']:
        picture=args.work/'preview'/name
        if picture.is_file():copy(picture,destination/name)
    validation = {'version': '5.0', 'build_id': 'gold-relief-native-bright-20261024', 'hardware_validation': 'pending',
                  'baseline_hardware_validation': 'Previous 5.0 passed on hardware according to user; new images require a new board check.',
                  'boards': release_builds, 'asset': read(asset.with_suffix('.json')),
                  'reexecuted': executed_count, 'unchanged_reverified': verified_count,
                  'current_passed_records': len(tests)+len(unchanged),
                  'tests': tests+unchanged, 'excluded_historical_records': historical,
                  'files_sha256': releases,
                  'rendering': '24 native 576x576 indexed views with per-view material palettes, aligned PackBits and FPGA interactive lighting; 720p output; 10 display frames per view, twice previous speed; scene-only twofold exposure curve with highlight protection; two 4MiB SDRAM slots.'}
    write(destination/'validation.json', validation)
    remember(ROOT/'VERSION')
    (ROOT/'VERSION').write_text('5.0\nbuild_id=gold-relief-native-bright-20261024\npublic_version_policy=fixed\n', encoding='utf-8')
    manifest.update(saved_at=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                    source_release='releases/relief_native_20261024', build_id='gold-relief-native-bright-20261024',
                    change_scope='Increase trophy source from 384x384 to native 576x576, double default rotation speed, apply scene-only 2x exposure with highlight protection, and use aligned PackBits, four-row directory caching, two 4MiB SDRAM slots and adaptive 4/64-word bursts. Preserve approved background, original confetti, photo/audio and controls.',
                    source_state='Current 5.0 source fingerprint matches both freshly rebuilt release images.',
                    hardware_validation='pending', release_builds=release_builds, release_files=releases,
                    current_recorded_test_count=len(tests)+len(unchanged),
                    regression_accounting={'current_passed': len(tests)+len(unchanged), 'reexecuted': executed_count,
                                           'unchanged_reverified': verified_count, 'excluded_historical': historical},
                    backup_directory=str(args.work/'baseline/5.0project'), relief_validation='releases/relief_native_20261024/validation.json')
    manifest['package_checks'].update(both_boards_recompiled=True, A_recompiled=True,
                                     B_qualified_firmware_reused=False, current_regressions='See releases/relief_native_20261024/validation.json; current fingerprints checked.')
    manifest['saved_rtl_files'] = len(list((ROOT/'common').rglob('*.v')))
    # TD GUI locks and active GUI logs are runtime state, not source artifacts.
    files = [p for p in ROOT.rglob('*') if p.is_file() and p.name != 'package_manifest.json'
             and not p.name.startswith('.lock') and not ('td_project/log/' in p.relative_to(ROOT).as_posix())]
    manifest['inventory_exclusions'] = ['package_manifest.json (self)', '**/.lock*', '**/td_project/log/**']
    manifest['files_sha256'] = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(files)}
    manifest['file_count'] = len(files)
    write(ROOT/'package_manifest.json', manifest)
    result = verify(strict=True)
    print(json.dumps({'published': releases, 'verification': result, 'builds': release_builds}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except BaseException:
        # Restore every touched file if copying or final integrity checks fail.
        # The keys have all been resolved and verified inside ROOT by remember.
        for path, content in reversed(list(_before.items())):
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
        raise
