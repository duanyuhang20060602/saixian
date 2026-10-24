"""Exercise imported early-preview/prefetch/timing behavior on the 5.6 RTL."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, re, subprocess, time

ROOT = Path(__file__).resolve().parents[1]
CACHE = ['common/photo_sd_cache.v', 'common/photo_color_format.v', 'common/photo_audio_link.v',
         'common/photo_sd_audio_stream.v', 'common/photo_sd/photo_dlt_reader.v', 'common/photo_sd/photo_dlt_header.v']
JOBS = {
    'timing': ('tb_switch_timing', ['tests/tb_switch_timing.v', 'common/photo_switch_timing.v'], []),
    'timing_control': ('tb_switch_timing_control', ['tests/tb_switch_timing_control.v', 'common/photo_switch_timing.v',
                       'common/photo_cached_control_a.v', 'common/photo_control.v', 'common/photo_uart.v'], []),
    'early_thumbnail': ('tb_thumbnail_early', ['tests/tb_thumbnail_early.v', 'common/photo_cached_control_a.v',
                        'common/photo_thumbnail.v', 'common/photo_uart.v'], ['THUMBNAIL_SIM']),
    'early_cancel': ('tb_thumbnail_early_cancel', ['tests/tb_thumbnail_early_cancel.v', 'common/photo_thumbnail.v'], ['THUMBNAIL_SIM']),
    'prefetch_compare': ('tb_prefetch_overlap', ['tests/tb_prefetch_overlap.v', 'tests/tb_two_slot_cache.v', *CACHE], ['WATER_SIM', 'VICTORY_SIM']),
    'prefetch_baseline_safety': ('tb', ['tests/tb_two_slot_cache.v', *CACHE], ['WATER_SIM', 'VICTORY_SIM']),
    'prefetch_early_safety': ('tb', ['tests/tb_two_slot_cache.v', *CACHE], ['WATER_SIM', 'VICTORY_SIM']),
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--only', nargs='+', choices=JOBS)
    parser.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    out = args.out.resolve()
    assert out.drive.upper() == 'E:'
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(TEMP='E:/Codex/Temp', TMP='E:/Codex/Temp', TMPDIR='E:/Codex/Temp')

    def run(name):
        started = time.monotonic()
        folder = out/name
        folder.mkdir(exist_ok=True)
        top, names, defines = JOBS[name]
        files = [ROOT/p for p in names]
        evidence = [*files, Path(__file__)]
        if name == 'prefetch_early_safety':
            original = files[0].read_text(encoding='utf-8')
            replaced = original.replace('.FORWARD_ONLY(1)) dut(', '.FORWARD_ONLY(1),.EARLY_PREFETCH(1)) dut(')
            assert replaced != original
            bench = folder/'tb_two_slot_early.v'
            bench.write_text(replaced, encoding='utf-8')
            files[0] = bench
            evidence.append(bench)
        hashes = {p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p):sha(p) for p in evidence}
        binary = folder/'simulation.vvp'
        result = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', *['-D'+d for d in defines],
                                 '-s', top, '-o', str(binary), *map(str, files)],
                                cwd=ROOT, env=env, capture_output=True, text=True)
        log = result.stdout+result.stderr
        if result.returncode == 0:
            result = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=ROOT, env=env,
                                    capture_output=True, text=True, timeout=300)
            log += result.stdout+result.stderr
        unchanged = all(sha(Path(p) if Path(p).is_absolute() else ROOT/p) == h for p,h in hashes.items())
        passed = result.returncode == 0 and 'PASS ' in log and unchanged and not re.search(r'(?im)^(FATAL:|ERROR:)', log)
        path = folder/'result.log'
        path.write_text(log, encoding='utf-8')
        print(name+': '+next((line for line in log.splitlines() if line.startswith('PASS ')), log), flush=True)
        return dict(test=name, passed=passed, seconds=round(time.monotonic()-started, 2),
                    inputs_sha256=hashes, inputs_unchanged=unchanged, log=str(path), log_sha256=sha(path))

    records = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for record in pool.map(run, args.only or JOBS):
            records.append(record)
            (out/'results.json').write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
    assert all(record['passed'] for record in records)


if __name__ == '__main__':
    main()
