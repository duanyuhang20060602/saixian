"""Focused regressions for the dual-board font integration and video guards."""
from pathlib import Path
import argparse, hashlib, json, subprocess

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    ram_init = out/'ip_init_map.vh'
    ram_init.write_text('localparam HEX_FILE="";\n', encoding='ascii')
    jobs = {
        'legacy_b': ('tb', ['tests/tb_typed_legacy_b.v', 'common/photo_typed_control_b.v',
                           'common/photo_uart.v'], []),
        'hmi': ('tb', ['tests/tb_typed_hmi.v', 'common/photo_typed_text_a.v',
                       'common/photo_text_crc.v', 'common/saixian_hmi_uart.v'], []),
        'osd': ('tb', ['tests/tb_typed_osd.v', 'common/audio_ui/saixian_osd_overlay.v'], []),
        'arbiter': ('tb', ['tests/tb_font_sector_arbiter.v', 'common/photo_sd_cache.v',
                           'common/photo_audio_link.v', 'common/photo_color_format.v',
                           'common/photo_sd_audio_stream.v', 'tests/ip_vendor_ram_adapter.v',
                           'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v'] +
                    [p.relative_to(ROOT).as_posix() for p in sorted((ROOT/'common/photo_sd').glob('*.v'))],
                    ['ERAM_SIM']),
        'preview_guard': ('tb_thumbnail_overlay', ['tests/tb_thumbnail_overlay.v',
                                                  'common/photo_thumbnail.v'], ['THUMBNAIL_SIM']),
        'preview_cancel': ('tb_thumbnail_early_cancel', ['tests/tb_thumbnail_early_cancel.v',
                                                       'common/photo_thumbnail.v'], ['THUMBNAIL_SIM']),
        'preview_pixels': ('tb_thumbnail_phase', ['tests/tb_thumbnail_phase.v',
                                                 'common/photo_thumbnail.v',
                                                 'common/photo_raster_delay.v'], ['THUMBNAIL_SIM']),
    }
    results = []
    for name, (top, sources, defines) in jobs.items():
        files = [ROOT/p for p in sources]
        hashes = {str(p): sha(p) for p in [Path(__file__), *files, ram_init]}
        binary = out/(name+'.vvp')
        compiled = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-I'+str(out), '-s', top,
                                   *['-D'+d for d in defines], '-o', str(binary), *map(str, files)],
                                  cwd=ROOT, capture_output=True, text=True)
        (out/(name+'_compile.log')).write_text(compiled.stdout+compiled.stderr, encoding='utf-8')
        compiled.check_returncode()
        run = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=ROOT,
                             capture_output=True, text=True, timeout=180)
        log = out/(name+'.log')
        log.write_text(run.stdout+run.stderr, encoding='utf-8')
        assert all(sha(Path(p)) == value for p, value in hashes.items()), 'Sources changed during test'
        passed = run.returncode == 0 and 'PASS' in run.stdout and 'FATAL' not in run.stdout
        results.append({'test': name, 'passed': passed, 'source_sha256': hashes,
                        'log': str(log), 'log_sha256': sha(log), 'defines': defines})
        (out/'results.json').write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')
        print(name+': '+run.stdout, flush=True)
        assert passed, name


if __name__ == '__main__':
    main()
