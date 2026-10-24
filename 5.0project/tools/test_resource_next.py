"""Reproduce 5.6 storage/validator proofs; write all generated files on E:."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, sys, time

ROOT = Path(__file__).resolve().parents[1]
VENDOR = Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
JOBS = ('native_geometry_memory', 'header', 'native_dry', 'behavioral_dry',
        'pitch', 'transport_compact', 'controls', 'cache', 'dlt', 'geometry')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run_unit(case, out):
    folder = out / case
    folder.mkdir(parents=True, exist_ok=True)
    files, flags, language = [], [], '-g2012'
    if case == 'native_geometry_memory':
        files = ['tests/tb_resource_next_memory.v', 'common/fluid/water_drop_small.v', 'common/fluid/water_cache.v']
        language = '-g2005'
    elif case == 'header':
        files = ['tests/tb_resource_next_header.v', 'common/photo_sd/photo_dlt_header.v',
                 'tests/reference/resource_next/photo_dlt_header_5_5.v']
    else:
        files = ['tests/tb_resource_next_dry.v', 'common/audio_ui/saixian_audio_pitch.v']
        if case == 'behavioral_dry':
            flags += ['-DVICTORY_SIM']
    paths = [ROOT / name for name in files]
    evidence = [*paths, Path(__file__)]
    if case.startswith('native_'):
        include = folder / 'ip_init_map.vh'
        include.write_text('localparam HEX_FILE=INIT_FILE=="water_inverse_low9.mif" ? "common/fluid/water_inverse_low9.hex":"";\n', encoding='ascii')
        paths += [ROOT / 'tests/ip_vendor_ram_adapter.v', VENDOR]
        evidence += [*paths[-2:], include]
        flags += ['-I' + str(folder)]
    checks = {}
    if case == 'native_geometry_memory':
        original = ROOT / 'common/fluid/water_inverse.hex'
        low = ROOT / 'common/fluid/water_inverse_low9.hex'
        mif = ROOT / 'common/fluid/water_inverse_low9.mif'
        words = [int(x, 16) for x in original.read_text().split()]
        lows = [int(x, 16) for x in low.read_text().split()]
        stored = {int(a, 16): int(v, 16) for a, v in re.findall(r'(?mi)^([0-9a-f]+)\s*:\s*([0-9a-f]+);', mif.read_text())}
        assert len(words) == len(lows) == len(stored) == 2048
        assert all(lows[i] == stored[i] == (v & 511) for i, v in enumerate(words))
        assert all(v < 512 for v in words[129:])
        evidence += [original, low, mif]
        checks = dict(exact_low9_rom_words=2048, high_bits_nonzero_only_at='1..128',
                      inverse_ram9k_before=4, inverse_ram9k_expected=2,
                      cache_tail_ram32k_before=2, cache_tail_ram9k_expected=4)
    hashes = {p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p): sha(p) for p in evidence}
    env = os.environ.copy()
    env.update(TEMP='E:/Codex/Temp', TMP='E:/Codex/Temp', TMPDIR='E:/Codex/Temp')
    started = time.monotonic()
    binary = folder / 'simulation.vvp'
    result = subprocess.run(['C:/iverilog/bin/iverilog.exe', language, '-Wall', *flags, '-s', 'tb',
                             '-o', str(binary), *map(str, paths)], cwd=ROOT, env=env, capture_output=True, text=True)
    log = result.stdout + result.stderr
    if result.returncode == 0:
        result = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=ROOT, env=env,
                                capture_output=True, text=True, timeout=180)
        log += result.stdout + result.stderr
    unchanged = all(sha(Path(p) if Path(p).is_absolute() else ROOT / p) == h for p, h in hashes.items())
    passed = result.returncode == 0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(ERROR:|FATAL:)', log)
    path = folder / 'result.log'
    path.write_text(log, encoding='utf-8')
    print(case + ': ' + next((line for line in log.splitlines() if line.startswith('PASS ')), log), flush=True)
    return dict(test=case, passed=passed, seconds=round(time.monotonic()-started, 2),
                inputs_sha256=hashes, inputs_unchanged=unchanged, measurements=checks,
                log=str(path), log_sha256=sha(path))


def normalize_pitch_annotations(records):
    # The unmodified 5.5 runner checks every output against the independent
    # release model. Its old descriptive memory counts are not measurements
    # of the 5.6 hardware; supply the new structural expectations explicitly.
    for record in records:
        if record['test'] in ('model', 'native_model'):
            values = record['measurements']
            values.pop('production_history_ram32_blocks', None)
            values.pop('dry_history_frames', None)
            values.update(expected_pitch_history_ram32k=5, expected_dry_tail_ram9k=1,
                          dry_delay_frames=1152, dry_retained_frames=1153,
                          allocation_note='Structural expectations; use routed build reports for actual device allocation.')
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--only', nargs='+', choices=JOBS)
    args = parser.parse_args()
    out = args.out.resolve()
    assert out.drive.upper() == 'E:'
    out.mkdir(parents=True, exist_ok=True)
    records = []
    for case in args.only or JOBS:
        if case in JOBS[:4]:
            records.append(run_unit(case, out))
            continue
        destination = out / case
        if case == 'pitch':
            import test_audio_pitch_b as suite
            suite.JOBS = ('native_model', 'transport', 'flow')
            extra = ['--only', *suite.JOBS, '--jobs', '3']
        elif case == 'controls':
            import test_audio_pitch_b as suite
            suite.JOBS = ('keys', 'volume')
            extra = ['--only', 'keys', 'volume', '--jobs', '2']
        elif case == 'transport_compact':
            import test_resource_research as suite
            extra = ['--only', 'transport_compact']
        elif case == 'cache':
            import test_animation_cache as suite
            extra = ['--only', 'two_slot_cache', '--jobs', '1']
        elif case == 'dlt':
            import test_audio_dlt_guard as suite
            extra = []
        else:
            import test_fx11_water as suite
            extra = ['--only', 'effects', 'dsp_effects', 'math', 'dsp_math', 'compact', 'cache',
                     'bandwidth_water', 'bandwidth_metal', 'bandwidth_tunnel', 'scanout_native', '--jobs', '2']
        sys.argv = [case, '--out', str(destination), *extra]
        suite.main()
        current = json.loads((destination/'results.json').read_text(encoding='utf-8'))
        records += normalize_pitch_annotations(current) if case == 'pitch' else current
    (out/'results.json').write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
    assert all(record['passed'] for record in records)


if __name__ == '__main__':
    main()
