"""Build/package the A-board refresh fix with immutable source hashes."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--board', choices=['a', 'b'], default='a')
parser.add_argument('--variant', choices=['refresh', 'link25_crc', 'mem67_staged', 'group4_staged', 'av_b_winners', 'fluid_drop', 'fluid_select', 'fluid_priority', 'fluid_smooth', 'fluid_second', 'fluid_second6', 'av_refresh6'], default='refresh')
parser.add_argument('--revalidate-routed', action='store_true',
                    help='Reapply corrected SDC to an existing routed design; HDL must match its snapshot')
args = parser.parse_args()
TD = ROOT / f'projects/board_{args.board}/src/td_project'
OUT = ROOT / 'delivery'
NAME = f'PHOTO_BOARD_{args.board.upper()}'
TAG = {'refresh':'whitebar_refresh','link25_crc':'whitebar_link25_crc','mem67_staged':'whitebar_mem67_staged','group4_staged':'whitebar_group4_staged','av_b_winners':'av_b_winners','fluid_drop':'fluid_drop','fluid_select':'fluid_select','fluid_priority':'fluid_priority','fluid_smooth':'fluid_smooth','fluid_second':'fluid_second','fluid_second6':'fluid_second6','av_refresh6':'av_refresh6'}[args.variant]
ARTIFACT = NAME + '_720P_V3_1_' + ('WHITEBAR_REFRESH_FIX' if args.variant == 'refresh' else 'WHITEBAR_LINK25_CRC' if args.variant == 'link25_crc' else 'WHITEBAR_MEM67_STAGED' if args.variant == 'mem67_staged' else 'WHITEBAR_GROUP4_STAGED' if args.variant == 'group4_staged' else 'AV_REFRESH6' if args.variant == 'av_refresh6' else 'FLUID_SECOND6' if args.variant == 'fluid_second6' else 'FLUID_SECOND' if args.variant == 'fluid_second' else 'FLUID_SMOOTH' if args.variant == 'fluid_smooth' else 'FLUID_PRIORITY' if args.variant == 'fluid_priority' else 'FLUID_SELECT' if args.variant == 'fluid_select' else 'FLUID_DROP' if args.variant == 'fluid_drop' else 'AV_B_WINNERS') + '.bit'
selected = {(TD / p).resolve() for p in json.loads((TD / 'sources.json').read_text())}
selected.update((TD.parent / 'user_source/constraints_source').glob('*'))
selected.update((TD.parent / 'user_source/hdl_source').rglob('*.mif'))
selected.update((TD.parent / 'user_source/hdl_source/include').glob('*.v'))
selected.update((ROOT / 'common').rglob('*.mif'))
selected.update([TD / 'sources.json', TD / f'{NAME}.al', TD / 'build_board.tcl'])

def hashes():
    return {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(selected) if p.is_file()}

snapshot = hashes()
OUT.mkdir(exist_ok=True)
snapshot_path = OUT / f'board_{args.board}_{TAG}_source_snapshot.json'
routed_hash = None
if args.revalidate_routed:
    prior = json.loads(snapshot_path.read_text())
    assert {p: h for p, h in snapshot.items() if not p.endswith('.sdc')} == {
        p: h for p, h in prior.items() if not p.endswith('.sdc')}, 'HDL/project changed since routing'
    routed_hash = hashlib.sha256((TD / f'{NAME}_pr.db').read_bytes()).hexdigest()
snapshot_path.write_text(json.dumps(snapshot, indent=2) + '\n')
start = time.time()
log_path = TD / (TAG + '_build.log')
script = 'build_board.tcl'
if args.revalidate_routed:
    shutil.copy2(log_path, OUT / f'board_{args.board}_{TAG}_routing_build.log')
    script = TAG + '_revalidate.tcl'
    (TD / script).write_text(f'''import_device eagle_s20.db -package EG4S20BG256
open_project {NAME}.al -single_run
import_db {NAME}_pr.db
clear_sdc -user
read_sdc ../user_source/constraints_source/BOARD_{args.board.upper()}_{'RECEIVER' if args.board == 'a' else 'SENDER'}_timing.sdc
update_timing -mode final
report_timing_status -file {NAME}_phy.ts
report_timing_summary -file {NAME}_pr.timing
report_timing_exception -file {NAME}_exception.timing
report_area -io_info -file {NAME}_phy.area
bitgen -bit {NAME}.bit
''')
with log_path.open('w') as log:
    run = subprocess.run(['C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe',
                          script], cwd=TD, stdout=log, stderr=subprocess.STDOUT)
assert run.returncode == 0, f'TD failed ({run.returncode}); see {log_path}'
assert hashes() == snapshot, 'Build sources changed during compilation'
assert 'USR-8159 CRITICAL-WARNING' not in log_path.read_text(errors='replace'), 'Constraint command failed'
timing_path = TD / f'{NAME}_pr.timing'
assert timing_path.stat().st_mtime >= start, 'Timing report was not regenerated'
timing = timing_path.read_text(errors='replace')
values = {key: float(re.search(key + r':\s*([-\d.]+)ns', timing)[1])
          for key in ['SWNS', 'STNS', 'HWNS', 'HTNS']}
assert values['SWNS'] >= 0 and values['HWNS'] >= 0 and values['STNS'] == values['HTNS'] == 0, values
bit = TD / f'{NAME}.bit'
assert bit.stat().st_mtime >= start, 'Bitstream was not regenerated'
target = OUT / ARTIFACT
shutil.copy2(bit, target)
area = (TD / f'{NAME}_phy.area').read_text(errors='replace')
resources = {key: int(re.search(r'^#' + key + r'\s+(\d+)', area, re.M)[1])
             for key in ['lut', 'reg', 'bram', 'bram32k', 'dsp']}
report = {'artifact': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
          'size_bytes': target.stat().st_size, 'timing_ns': values, 'resources': resources,
          'build_seconds': round(time.time() - start, 1), 'board_validation': 'pending',
          'build_mode': 'routed SDC revalidation' if args.revalidate_routed else 'full synthesis/place/route/bitgen',
          'routed_database_sha256': routed_hash,
          'change': ('Local accepted-PCM timestamps for AV snapshots; retry due metadata until CRC success; one-microsecond SPI CS gap; RGB565 six/RGB888 ten cycles and effects unchanged' if args.variant == 'av_refresh6' else 'RGB565 six added write-settle cycles; RGB888 ten-cycle guard latched per request; card/accordion/ribbon and 48-step timeline unchanged; both boards rebuilt' if args.variant == 'fluid_second6' else 'RGB565 zero added write-settle cycles; RGB888 ten-cycle guard latched per request; shared card/accordion/ribbon geometry; menu/HMI effects 11-13; 48-frame timeline retained; both boards rebuilt' if args.variant == 'fluid_second' else 'All transitions use 48 per-frame steps; eased slide and linear direct fluid phase; no half-rate phase holds; reduced water temporal phase speed; B unchanged' if args.variant == 'fluid_smooth' else 'Shared line-cache metal/curl/column transitions, five-bit selection, independent music edge light, aligned final RGB/DE/SOF/EOL' if args.variant == 'fluid_priority' else 'Water ripple is effect 7; default random; eligibility-aware non-repeating random pool; unchanged RGB565 fluid datapath' if args.variant == 'fluid_select' else 'RGB565 waterdrop; B filtered auxiliary pass; 3 combined slots; A 8-row small-halo cache' if args.variant == 'fluid_drop' else 'A audio FIFO4096; FFT/wave on B; CRC32 metadata on existing SPI; shared red/blue victory renderer and patch ROM' if args.variant == 'av_b_winners' else '50MHz SDRAM isolated four-word writes with ten-cycle settling, staged boot progress from 25%, 25MHz link and CRC32' if args.variant == 'group4_staged' else '66.667MHz SDRAM above documented continuous-write minimum, stage-based boot progress, 25MHz link and CRC32' if args.variant == 'mem67_staged' else '25MHz board link, frame CRC32 admission, retained error origin, SDRAM refresh guards' if args.variant == 'link25_crc' else f'Suppress board {args.board.upper()} SDRAM read/write commands and FIFO pops during refresh'),
          'source_sha256': snapshot}
for source, suffix in [(log_path, 'build.log'), (timing_path, 'timing.txt'),
                       (TD / f'{NAME}_phy.area', 'area.txt')]:
    shutil.copy2(source, OUT / (f'board_{args.board}_{TAG}_' + suffix))
(OUT / (f'board_{args.board}_v31_{TAG}' + ('_fix.json' if args.variant == 'refresh' else '.json'))).write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'source_sha256'}, indent=2), flush=True)
