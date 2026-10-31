"""Verify preserved TITLE2 boot banks with the integrated B UART controller."""
from pathlib import Path
import argparse, hashlib, json, subprocess
ROOT = Path(__file__).resolve().parents[1]


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    out = parser.parse_args().out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    original = ROOT/'tests/tb_boot_catalog_status.v'
    body = original.read_text().replace('photo_control_b #', 'photo_typed_control_b #')
    body = body.replace('initial begin\n repeat(5)',
        'always @(negedge clk)if(!rst && valid)begin\n'
        ' if(wd!==32\'h13579bdf || wl!==5\'d4)$fatal(1,"boot font data/length changed");\n'
        'end\ninitial begin\n repeat(5)')
    bench = out/'boot_font.v'
    bench.write_text(body, encoding='utf-8')
    files = [bench, ROOT/'common/photo_typed_control_b.v', ROOT/'common/photo_cached_control_a.v',
             ROOT/'common/photo_control.v', ROOT/'common/photo_uart.v',
             ROOT/'common/audio_ui/saixian_font_rom.v', ROOT/'tests/title_font_ram_model.v']
    hashes = {str(p): digest(p) for p in [Path(__file__), original, *files]}
    binary = out/'boot_font.vvp'
    build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', 'tb', '-o', str(binary),
                            *map(str, files)], capture_output=True, text=True)
    log_text = build.stdout+build.stderr
    passed = False
    if build.returncode == 0:
        run = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=out,
                             capture_output=True, text=True, timeout=300)
        log_text += run.stdout+run.stderr
        passed = run.returncode == 0 and 'PASS real duplex UART boot catalog' in log_text and 'FATAL' not in log_text
    log = out/'boot_font.log'
    log.write_text(log_text, encoding='utf-8')
    assert all(digest(Path(p)) == h for p, h in hashes.items())
    result = {'test': 'typed_b_legacy_font_boot', 'passed': passed, 'source_sha256': hashes,
              'log': str(log), 'log_sha256': digest(log)}
    (out/'results.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(log_text[-3000:], flush=True)
    assert passed


if __name__ == '__main__':
    main()
