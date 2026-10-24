"""Reproducible old/new award controls, HMI and catalog regressions.

The catalog scanner uses production parsers and real package headers. Cache
tests model SD decoders only at their scheduler boundary and perform complete
691200-word award loads. Every test records immutable input and fixture hashes.
"""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, re, struct, subprocess, time

ROOT = Path(__file__).resolve().parents[1]
WORK = Path('E:/Codex/Work/saixian-relief-integration-20261023')
VENDOR = Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')
CONTROL = ['common/photo_cached_control_a.v', 'common/photo_control.v', 'common/photo_uart.v', 'common/photo_link.v']
CACHE = ['common/photo_sd_cache.v', 'common/photo_color_format.v', 'common/photo_audio_link.v', 'common/photo_sd_audio_stream.v']
PITCH = ['common/photo_audio_link.v', 'common/photo_audio_features.v', 'common/photo_audio_pitch_b.v',
         'common/audio_ui/saixian_audio_pitch.v', 'common/audio_ui/saixian_audio_repair.v', 'common/audio_ui/photo_audio_cue_samples.v']
JOBS = {
    'hmi_legacy': ('tb_hmi', ['tests/tb_hmi.v', 'common/saixian_hmi_uart.v'], []),
    'hmi_relief': ('tb', ['tests/tb_relief_hmi.v', 'common/saixian_hmi_uart.v'], []),
    'control_legacy': ('tb', ['tests/tb_award_v5_control.v', *CONTROL], []),
    'control_relief': ('tb', ['tests/tb_relief_control.v', *CONTROL], []),
    'control_wait_catalog': ('tb', ['tests/tb_relief_control.v', *CONTROL], ['-P', 'tb.WAIT_CATALOG=1']),
    'control_only_relief': ('tb', ['tests/tb_relief_control.v', *CONTROL], ['-P', 'tb.ONLY_RELIEF=1']),
    'motion': ('tb', ['tests/tb_relief_motion.v', 'common/photo_relief_motion.v'], []),
    'catalog': ('tb', ['tests/tb_relief_catalog_scan.v', 'common/photo_sd/bmp_read.v',
                        'common/photo_sd/photo_dlt_header.v', 'common/photo_sd/saixian_media_header.v'], []),
    'catalog_reverse': ('tb', ['tests/tb_relief_catalog_scan.v', 'common/photo_sd/bmp_read.v',
                        'common/photo_sd/photo_dlt_header.v', 'common/photo_sd/saixian_media_header.v'], ['-P', 'tb.REVERSE=1']),
    'cache': ('tb', ['tests/tb_relief_cache_catalog.v', *CACHE], ['-DVICTORY_SIM']),
    'cache_reverse': ('tb', ['tests/tb_relief_cache_catalog.v', *CACHE], ['-DVICTORY_SIM', '-P', 'tb.REVERSE=1']),
    'cache_paused': ('tb', ['tests/tb_relief_cache_catalog.v', *CACHE], ['-DVICTORY_SIM', '-P', 'tb.PAUSED=1']),
    'cache_paused_reverse': ('tb', ['tests/tb_relief_cache_catalog.v', *CACHE], ['-DVICTORY_SIM', '-P', 'tb.PAUSED=1', '-P', 'tb.REVERSE=1']),
    'fx_controls': ('tb', ['tests/fx11_water/tb_controls.v', 'common/saixian_hmi_uart.v',
                         'common/photo_unified_settings_controller.v'], []),
    'keys': ('tb', ['tests/tb_pitch_keys.v', *PITCH], ['-DVICTORY_SIM']),
    'volume': ('tb', ['tests/tb_pitch_volume.v', *PITCH], ['-DVICTORY_SIM']),
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def catalog_fixtures(folder, old, new, reverse):
    # Valid 1280x720 BGR24 BMP metadata; no pixels are read during scanning.
    bmp = bytearray(512)
    bmp[:2] = b'BM'
    size = 54 + 1280 * 720 * 3
    struct.pack_into('<I', bmp, 2, size)
    struct.pack_into('<I', bmp, 10, 54)
    struct.pack_into('<IiiHHI', bmp, 14, 40, 1280, 720, 1, 24, 0)
    a, b = old.read_bytes()[:512], new.read_bytes()[:512]
    assert a[:8] == b'SXDLT005' and b[:8] == b'SXDLT008'
    headers = [bytes(bmp)] * 6 + ([b, a, b, a] if reverse else [a, b, a, b])
    lengths = [size] * 6 + [struct.unpack_from('<I', h, 20)[0] for h in headers[6:]]
    sectors = [0]
    for n in lengths:
        sectors.append(sectors[-1] + (n + 511) // 512)
    hfile, sfile = folder/'catalog_headers.hex', folder/'catalog_sectors.hex'
    hfile.write_text(''.join(f'{v:02x}\n' for h in headers for v in h), encoding='ascii')
    sfile.write_text(''.join(f'{v:08x}\n' for v in sectors), encoding='ascii')
    return [hfile, sfile, old, new]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', type=Path, default=WORK/'control_regressions')
    ap.add_argument('--asset', type=Path)
    ap.add_argument('--only', nargs='+', choices=JOBS)
    ap.add_argument('--jobs', type=int, default=3)
    args = ap.parse_args()
    out = args.out.resolve()
    assert out.drive.upper() == 'E:', out
    out.mkdir(parents=True, exist_ok=True)
    temp = out/'tmp'; temp.mkdir(exist_ok=True)
    env = os.environ.copy()
    env.update(TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp), PYTHONDONTWRITEBYTECODE='1')
    asset = args.asset or (ROOT/'award_media/RELIEF720.DLT' if (ROOT/'award_media/RELIEF720.DLT').exists() else WORK/'media/RELIEF720.DLT')
    def run(name):
        started = time.monotonic()
        folder = out/name; folder.mkdir(exist_ok=True)
        top, paths, flags = JOBS[name]
        files = [ROOT/p for p in paths]
        fixtures = catalog_fixtures(folder, ROOT/'award_media/AWARD720.DLT', asset, name.endswith('reverse')) if name.startswith('catalog') else []
        if name.startswith('catalog'):
            files.extend([ROOT/'tests/ip_vendor_ram_adapter.v', VENDOR])
            include = folder/'ip_init_map.vh'
            include.write_text('localparam HEX_FILE="";\n', encoding='ascii')
            fixtures.append(include)
        evidence = [*files, Path(__file__), *fixtures]
        hashes = {p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p): sha(p) for p in evidence}
        binary = folder/'simulation.vvp'
        command = ['C:/iverilog/bin/iverilog.exe', '-g2012', '-I'+str(folder), '-s', top, *flags, '-o', str(binary), *map(str, files)]
        result = subprocess.run(command, cwd=folder, env=env, capture_output=True, text=True)
        log = result.stdout + result.stderr
        if result.returncode == 0:
            # Pitch tests resolve checked-in coefficient/sample ROMs from ROOT.
            cwd = ROOT if name in ('keys', 'volume') else folder
            result = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=cwd, env=env,
                                    capture_output=True, text=True, timeout=600)
            log += result.stdout + result.stderr
        unchanged = all(sha(p) == hashes[p.relative_to(ROOT).as_posix() if p.is_relative_to(ROOT) else str(p)] for p in evidence)
        passed = result.returncode == 0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)', log) and unchanged
        logpath = out/(name+'.log'); logpath.write_text(log, encoding='utf-8')
        print(name+': '+next((line for line in log.splitlines() if line.startswith('PASS ')), log[-2200:]), flush=True)
        return dict(test=name, passed=passed, seconds=round(time.monotonic()-started, 2), inputs_sha256=hashes,
                    inputs_unchanged=unchanged, flags=flags, log=str(logpath), log_sha256=sha(logpath))
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        records = list(pool.map(run, args.only or JOBS))
    dest = out/'results.json'
    old = json.loads(dest.read_text(encoding='utf-8')) if dest.exists() else []
    old = [r for r in old if r['test'] not in {r['test'] for r in records}]
    dest.write_text(json.dumps(old+records, indent=2)+'\n', encoding='utf-8')
    if not all(r['passed'] for r in records):
        raise SystemExit(1)

if __name__ == '__main__':
    main()
