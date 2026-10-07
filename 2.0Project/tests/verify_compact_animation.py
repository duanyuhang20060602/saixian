"""Compare the candidate raster with the accepted Git baseline, not itself."""
import argparse
from pathlib import Path
import subprocess

BASELINE = '6b93dddf3f690c3b335ef3e86ce83e5045387575'

def run(work, baseline):
    work.mkdir(parents=True, exist_ok=True)
    source = (baseline.read_text() if baseline else subprocess.check_output([
        'git', 'show', BASELINE+':2.0Project/src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v'
    ]).decode())
    for name in ('saixian_battle_result_fx','saixian_victory_atlas','saixian_red_victory_atlas','saixian_sprint_atlas'):
        source = source.replace(name, name+'_ref')
    source = source.replace('_ref.hex', '.hex').replace('_ref.mif', '.mif')
    reference = work/'animation_reference.v'
    reference.write_text(source)
    exe = work/'animation_equivalence.vvp'
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DVICTORY_SIM','-s','tb_compact_animation_equivalence',
                    '-o',str(exe),'tests/tb_compact_animation_equivalence.v',
                    'src/user_source/hdl_source/saixian_battle_result_fx_pipelined.v',str(reference)],check=True)
    subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],check=True)

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--work',type=Path,required=True);p.add_argument('--baseline',type=Path)
    a=p.parse_args();run(a.work,a.baseline)
