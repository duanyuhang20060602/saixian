"""Validate selected V4 ports against cooperate, with per-case input hashes."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
JOBS = {
    'tb_v4_uart_equivalence': ['common/photo_uart.v', 'tests/reference/v4_port/photo_uart.v'],
    'tb_v4_audio_rate': ['common/photo_audio_link.v'],
    'tb_v4_award_equivalence': ['common/award_fx.v', 'common/award_sprite_rom.v',
                                'tests/reference/v4_port/award_fx.v'],
    'tb_v4_battle_equivalence': ['common/saixian_battle_result_fx_pipelined.v',
                                 'tests/reference/v4_port/saixian_battle_result_fx_pipelined.v'],
    'tb_boot_audio_sync': ['common/photo_boot_screen.v', 'common/photo_audio_link.v',
                           'common/photo_audio_features.v', 'common/audio_ui/saixian_audio_repair.v',
                           'common/audio_ui/photo_audio_cue_samples.v'],
    'tb_audio_transport_repair': ['common/photo_audio_link.v', 'common/photo_audio_features.v',
                                   'common/audio_ui/saixian_audio_repair.v',
                                   'common/audio_ui/photo_audio_cue_samples.v'],
    'tb_v4_transition_48': ['common/photo_display_pipe.v', 'common/saixian_transition.v'],
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=Path('E:/Codex/Work/cooperate-v4-port-20261018/tests'))
    parser.add_argument('--only', nargs='+', choices=JOBS)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    iv = Path(os.environ.get('IVERILOG', 'C:/iverilog/bin/iverilog.exe'))
    vvp = iv.with_name('vvp.exe')
    environment = os.environ.copy()
    temp = Path('E:/Codex/Temp/cooperate-v4-port-tests')
    temp.mkdir(parents=True, exist_ok=True)
    environment.update(TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp))
    report = out/'results.json'
    results = json.loads(report.read_text()) if args.only and report.exists() else []
    for name, deps in JOBS.items():
        if args.only and name not in args.only:
            continue
        paths = ['tests/' + name + '.v', *deps]
        # ROM data affect differential rendering even though they are not HDL arguments.
        inputs = set(paths)
        if 'battle' in name:
            inputs.update(p.relative_to(ROOT).as_posix() for p in
                          (ROOT/'src/board_a/user_source/hdl_source').glob('*.hex'))
        before = {p: digest(ROOT/p) for p in sorted(inputs)}
        started = time.monotonic()
        binary = out/(name+'.vvp')
        compiled = subprocess.run([str(iv), '-g2012', '-DVICTORY_SIM', '-s', name,
                                   '-o', str(binary), *paths], cwd=ROOT, env=environment,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (out/(name+'_compile.log')).write_text(compiled.stdout, encoding='utf-8')
        if compiled.returncode:
            print(compiled.stdout, flush=True)
            raise SystemExit('Compilation failed: '+name)
        with (out/(name+'.log')).open('w', encoding='utf-8') as log:
            result = subprocess.run([str(vvp), str(binary)], cwd=ROOT, env=environment,
                                    stdout=log, stderr=subprocess.STDOUT, timeout=600)
        output = (out/(name+'.log')).read_text(encoding='utf-8')
        unchanged = before == {p: digest(ROOT/p) for p in sorted(inputs)}
        passed = (result.returncode == 0 and 'PASS' in output and unchanged
                  and not re.search(r'(?im)^(ERROR:|FATAL:)', output))
        results = [item for item in results if item['test'] != name]
        results.append({'test': name, 'passed': passed, 'seconds': round(time.monotonic()-started, 2),
                        'inputs_unchanged': unchanged, 'inputs_sha256': before,
                        'log_sha256': digest(out/(name+'.log'))})
        report.write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')
        print(name+': '+output.strip(), flush=True)
        if not passed:
            raise SystemExit(1)
    print('PASS selected V4 port regressions: '+str(len(results)), flush=True)

if __name__ == '__main__':
    main()
