"""Reproduce 5.5 resource proofs without creating Markdown or archives."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, sys, time

ROOT = Path(__file__).resolve().parents[1]
VENDOR = Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def native(case, out):
    folder = out / case
    folder.mkdir(parents=True, exist_ok=True)
    if case == 'compact_pcm_native':
        names = ['tests/tb_compact_pcm_fifo.v', 'common/photo_sd_cache.v',
                 'common/photo_audio_link.v', 'common/photo_sd_audio_stream.v']
    elif case == 'transport_compact':
        names = ['tests/tb_pitch_transport_compact.v', 'common/photo_sd_cache.v',
                 'common/photo_audio_link.v', 'common/photo_audio_features.v',
                 'common/photo_audio_pitch_b.v', 'common/audio_ui/saixian_audio_pitch.v',
                 'common/audio_ui/saixian_audio_repair.v', 'common/audio_ui/photo_audio_cue_samples.v']
    else:
        names = ['tests/tb_repair_packed8.v',
                 'tests/reference/resource_research/audio_repair_5_4.v',
                 'common/audio_ui/saixian_audio_repair.v']
    files = [ROOT / name for name in names]
    files += [ROOT / 'tests/ip_vendor_ram_adapter.v', VENDOR]
    include = folder / 'ip_init_map.vh'
    include.write_text('localparam HEX_FILE="";\n', encoding='ascii')
    evidence = [*files, include, Path(__file__)]
    before = {p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p): sha(p) for p in evidence}
    env = os.environ.copy()
    temp = Path('E:/Codex/Temp/resource-research-tests')
    temp.mkdir(parents=True, exist_ok=True)
    env.update(TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp))
    binary = folder / 'simulation.vvp'
    start = time.monotonic()
    flags = ['-DVICTORY_SIM'] if case == 'transport_compact' else []
    run = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', *flags, '-I' + str(folder),
                          '-s', 'tb', '-o', str(binary), *map(str, files)],
                         cwd=ROOT, env=env, capture_output=True, text=True)
    log = run.stdout + run.stderr
    if run.returncode == 0:
        run = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=ROOT,
                             env=env, capture_output=True, text=True, timeout=600)
        log += run.stdout + run.stderr
    path = folder / 'result.log'
    path.write_text(log, encoding='utf-8')
    unchanged = all(sha(Path(p) if Path(p).is_absolute() else ROOT / p) == h for p, h in before.items())
    passed = run.returncode == 0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)', log) and unchanged
    print(log, flush=True)
    return dict(test=case, passed=passed, seconds=round(time.monotonic()-start, 2),
                inputs_sha256=before, log=str(path), log_sha256=sha(path))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--only', nargs='+', choices=['compact_pcm_native', 'repair_native', 'transport_compact',
                        'pitch', 'cache', 'geometry', 'scanout'])
    args = parser.parse_args()
    out = args.out.resolve()
    assert out.drive.upper() == 'E:', 'Keep generated proof artifacts on E:'
    out.mkdir(parents=True, exist_ok=True)
    selected = args.only or ['compact_pcm_native', 'repair_native', 'transport_compact', 'pitch', 'cache', 'geometry', 'scanout']
    records = []
    for case in selected:
        if case in ('compact_pcm_native', 'repair_native', 'transport_compact'):
            records.append(native(case, out))
            continue
        if case == 'pitch':
            import test_audio_pitch_b as suite
            suite.JOBS = ('native_model', 'transport', 'flow')
            arguments = ['--only', *suite.JOBS, '--jobs', '3']
        elif case == 'cache':
            import test_animation_cache as suite
            arguments = ['--only', 'two_slot_cache', '--jobs', '1']
        else:
            import test_fx11_water as suite
            names = ['scanout_native'] if case == 'scanout' else [
                'effects', 'dsp_effects', 'bandwidth_water', 'bandwidth_metal', 'bandwidth_tunnel']
            arguments = ['--only', *names, '--jobs', '2']
        destination = out / case
        sys.argv = [case, '--out', str(destination), *arguments]
        suite.main()
        records += json.loads((destination / 'results.json').read_text(encoding='utf-8'))
    (out / 'results.json').write_text(json.dumps(records, indent=2) + '\n', encoding='utf-8')
    if not all(r['passed'] for r in records):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
