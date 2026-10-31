"""Exercise real UART publication and fragmented TF font reads across clocks."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    spec = importlib.util.spec_from_file_location('fat_cases', ROOT/'tools/test_font_fat.py')
    model = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(model)
    sectors = model.make(True, 2048, 1, None)
    (out/'lbas.hex').write_text(''.join(f'{n:08x}\n' for n in sorted(sectors)))
    (out/'blocks.hex').write_text(''.join(f'{b:02x}\n' for n in sorted(sectors) for b in sectors[n]))
    font_path = ROOT/'sd_config/TF字库/FONTS.BIN'
    (out/'font.hex').write_text(''.join(f'{b:02x}\n' for b in font_path.read_bytes()))
    files = ['tests/tb_typed_text_slow.v', 'common/photo_text_crc.v',
             'common/photo_typed_text_a.v', 'common/photo_typed_text_b.v',
             'common/photo_typed_control_b.v', 'common/audio_ui/saixian_font_rom.v',
             'tests/title_font_ram_model.v', 'common/photo_cached_control_a.v',
             'common/photo_control.v', 'common/photo_uart.v',
             'common/photo_font_fat.v', 'common/photo_font_file_b.v']
    sources = [ROOT/f for f in files]
    evidence = [Path(__file__), ROOT/'tools/test_font_fat.py', font_path, *sources,
                *[out/n for n in ('lbas.hex', 'blocks.hex', 'font.hex')]]
    hashes = {str(p): digest(p) for p in evidence}
    binary = out/'uart_slow.vvp'
    build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-DTYPED_TEXT_SIM',
                            '-s', 'tb', '-o', str(binary), *map(str, sources)], capture_output=True, text=True)
    (out/'compile.log').write_text(build.stdout+build.stderr, encoding='utf-8')
    build.check_returncode()
    run = subprocess.run(['C:/iverilog/bin/vvp.exe', '-i', str(binary), f'+sectors={len(sectors)}'],
                         cwd=out, capture_output=True, text=True, timeout=600)
    log = out/'uart_slow.log'
    log.write_text(run.stdout+run.stderr, encoding='utf-8')
    passed = run.returncode == 0 and 'PASS slow FAT UART' in run.stdout and 'FATAL' not in run.stdout
    assert all(digest(Path(p)) == sha for p, sha in hashes.items())
    result = {'test': 'uart_slow_fat', 'passed': passed, 'source_sha256': hashes,
              'log': str(log), 'log_sha256': digest(log), 'glyph_rows_compared': 256,
              'scope': 'Two Chinese glyphs and ASCII, independent clocks, fragmented FAT, coincident final byte/end, CRC corruption and one lost ACK.'}
    (out/'results.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(run.stdout, flush=True)
    assert passed


if __name__ == '__main__':
    main()
