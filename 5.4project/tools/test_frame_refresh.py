"""Reproduce stored frame damage, then check the refresh admission fix."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--board', choices=['a', 'b'], default='a')
args = parser.parse_args()
IV = Path(os.environ.get('IVERILOG', 'C:/Users/MR.HUSKY/Desktop/qian/.tools/iverilog/bin/iverilog.exe'))
OUT = ROOT / 'tests/results'
OUT.mkdir(exist_ok=True)
SD = ROOT / f'src/board_{args.board}/user_source/hdl_source/SD'
shared = [ROOT / 'tests/tb_frame_refresh.v', SD / 'frame_read_write.v']
shared += [ROOT / f'src/board_{args.board}/user_source/hdl_source/IP' / p
           for p in ['afifo_32_16_256.v', 'afifo_16_32_256.v']]
report = []
for before in [True, False]:
    variants = []
    for stem, signal in [('read', 'rd'), ('write', 'wr')]:
        source = SD / f'frame_fifo_{stem}.v'
        if before:
            text = source.read_text(encoding='utf-8')
            replacements = {
                f'assign App_{signal}_en = App_{signal}_en_d0 && !Sdr_init_ref_vld;':
                f'assign App_{signal}_en = App_{signal}_en_d0;',
                ' && !Sdr_init_ref_vld) begin' if stem == 'read' else ' && !Sdr_init_ref_vld)':
                ') begin' if stem == 'read' else ')',
            }
            for old, new in replacements.items():
                assert text.count(old) == 1, old
                text = text.replace(old, new)
            source = OUT / f'board_{args.board}_frame_fifo_{stem}_without_refresh_guard.v'
            source.write_text(text, encoding='utf-8')
        variants.append(source)
    name = f'board_{args.board}_frame_refresh_' + ('before' if before else 'after')
    sources = shared + variants
    executable = OUT / (name + '.vvp')
    subprocess.run([str(IV), '-g2012', *(['-DEXPECT_REFRESH_FAILURE'] if before else []),
                    '-s', 'tb_frame_refresh', '-o', str(executable),
                    *map(str, sources)], cwd=ROOT, check=True)
    result = subprocess.run([str(IV.with_name('vvp.exe')), str(executable)], cwd=ROOT,
                            capture_output=True, text=True, timeout=120)
    log = result.stdout + result.stderr
    (OUT / (name + '.log')).write_text(log)
    print(log, flush=True)
    passed = result.returncode == 0 and log.count('PASS') == 4 and 'FATAL' not in log
    report.append({'test': name, 'passed': passed, 'source_sha256': {
        p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}})
    (OUT / f'board_{args.board}_frame_refresh_results.json').write_text(json.dumps(report, indent=2) + '\n')
    if not passed:
        raise SystemExit(result.returncode or 1)
