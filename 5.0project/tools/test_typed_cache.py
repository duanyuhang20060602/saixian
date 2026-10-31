"""Exercise the production glyph-cache DP RAM with the vendor model."""
from pathlib import Path
import argparse, hashlib, json, subprocess

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    init = out/'ip_init_map.vh'
    init.write_text('localparam HEX_FILE="";\n', encoding='ascii')
    files = [ROOT/'tests/tb_typed_cache_vendor.v', ROOT/'common/photo_typed_text_b.v',
             ROOT/'tests/ip_vendor_ram_adapter.v',
             Path('C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/ip/depot/AXI_Ethernet_Lite_1.0/AXI_Ethernet_Lite/RTL/ram_infer.v')]
    hashes = {str(p): digest(p) for p in [Path(__file__), init, *files]}
    binary = out/'cache.vvp'
    build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-I'+str(out),
                            '-s', 'tb', '-o', str(binary), *map(str, files)],
                           cwd=ROOT, capture_output=True, text=True)
    (out/'compile.log').write_text(build.stdout+build.stderr, encoding='utf-8')
    build.check_returncode()
    run = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=out,
                         capture_output=True, text=True, timeout=120)
    log = out/'cache.log'
    log.write_text(run.stdout+run.stderr, encoding='utf-8')
    passed = run.returncode == 0 and 'PASS' in run.stdout and 'FATAL' not in run.stdout
    assert all(digest(Path(p)) == sha for p, sha in hashes.items()), 'Test inputs changed'
    (out/'results.json').write_text(json.dumps({'passed': passed, 'source_sha256': hashes,
                                               'log': str(log), 'log_sha256': digest(log)}, indent=2)+'\n', encoding='utf-8')
    print(run.stdout+run.stderr, flush=True)
    assert passed


if __name__ == '__main__':
    main()
