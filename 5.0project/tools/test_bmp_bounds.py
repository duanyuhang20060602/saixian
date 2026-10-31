"""Check exact file-byte boundaries and every native 720p decoded pixel."""
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
    records = []
    for name, top, bench in [('boundaries', 'tb', 'tb_bmp_bounds.v'), ('native_image', 'tb_bmp', 'tb_bmp.v')]:
        files = [ROOT/'tests'/bench, ROOT/'common/photo_sd/bmp_read.v',
                 ROOT/'common/photo_sd/saixian_media_header.v', ROOT/'common/photo_sd/photo_dlt_header.v',
                 ROOT/'tests/native_unused_bram.v']
        hashes = {str(p): digest(p) for p in [Path(__file__), *files]}
        binary = out/(name+'.vvp')
        build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', top, '-o', str(binary),
                                *map(str, files)], capture_output=True, text=True)
        log_text = build.stdout+build.stderr
        passed = False
        if build.returncode == 0:
            run = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=out,
                                 capture_output=True, text=True, timeout=300)
            log_text += run.stdout+run.stderr
            passed = run.returncode == 0 and 'PASS ' in log_text and 'FATAL' not in log_text
        log = out/(name+'.log')
        log.write_text(log_text, encoding='utf-8')
        assert all(digest(Path(p)) == h for p, h in hashes.items())
        records.append({'test': name, 'passed': passed, 'source_sha256': hashes,
                        'log': str(log), 'log_sha256': digest(log)})
        (out/'results.json').write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
        print(name+': '+log_text[-2400:], flush=True)
        assert passed


if __name__ == '__main__':
    main()
