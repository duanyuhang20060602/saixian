"""Compare bounded sector decoding with the immutable f6 stream reader."""
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
    files = [ROOT/'tests/tb_audio_stream_window.v', ROOT/'tests/reference/audio_stream_before.v',
             ROOT/'common/photo_sd_audio_stream.v']
    hashes = {str(p): digest(p) for p in [Path(__file__), *files]}
    binary = out/'audio_window.vvp'
    build = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', 'tb', '-o', str(binary),
                            *map(str, files)], capture_output=True, text=True)
    log_text = build.stdout+build.stderr
    if build.returncode == 0:
        run = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=out,
                             capture_output=True, text=True, timeout=60)
        log_text += run.stdout+run.stderr
        passed = run.returncode == 0 and 'PASS audio sector windows' in log_text and 'FATAL' not in log_text
    else:
        passed = False
    log = out/'audio_window.log'
    log.write_text(log_text, encoding='utf-8')
    assert all(digest(Path(p)) == h for p, h in hashes.items())
    result = {'test': 'audio_sector_window', 'passed': passed, 'source_sha256': hashes,
              'log': str(log), 'log_sha256': digest(log)}
    (out/'results.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(log_text, flush=True)
    assert passed


if __name__ == '__main__':
    main()
