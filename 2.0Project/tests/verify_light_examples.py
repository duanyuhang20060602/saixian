"""Compare new lightweight RTL with the preserved, board-tested sources."""
import argparse
from pathlib import Path
import subprocess


def run(work: Path, baseline: Path):
    work.mkdir(parents=True, exist_ok=True)
    groups = [
        ('tb_light_frame_equivalence', ['SD/frame_fifo_read.v']),
        ('tb_light_timers_equivalence', ['saixian_key_debounce.v', 'SD/seg_scan.v']),
    ]
    for top, sources in groups:
        references = []
        for source in sources:
            name = Path(source).stem
            text = (baseline / Path(source).name).read_text(encoding='utf-8-sig')
            text = text.replace(name, name + '_ref')
            target = work / (name + '_ref.v')
            target.write_text(text, encoding='utf-8')
            references.append(str(target))
        exe = work / (top + '.vvp')
        subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', '-s', top,
                        '-o', str(exe), 'tests/' + top + '.v',
                        *['src/user_source/hdl_source/' + s for s in sources],
                        *references], check=True)
        subprocess.run(['C:/iverilog/bin/vvp.exe', str(exe)], check=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--baseline', type=Path, required=True)
    args = p.parse_args()
    run(args.work, args.baseline)
