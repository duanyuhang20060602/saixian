import argparse
from pathlib import Path
import subprocess

BASELINE='6b93dddf3f690c3b335ef3e86ce83e5045387575'

def run(work):
    work.mkdir(parents=True,exist_ok=True)
    source=subprocess.check_output(['git','show',BASELINE+':2.0Project/src/user_source/hdl_source/saixian_osd_overlay.v']).decode()
    source=source.replace('saixian_osd_overlay','saixian_osd_overlay_ref').replace('saixian_pcm_snapshot','saixian_pcm_snapshot_ref')
    reference=work/'osd_reference.v';reference.write_text(source)
    exe=work/'osd_equivalence.vvp'
    subprocess.run(['C:/iverilog/bin/iverilog.exe','-g2012','-DVICTORY_SIM','-s','tb_compact_osd_equivalence',
                    '-o',str(exe),'tests/tb_compact_osd_equivalence.v',
                    'src/user_source/hdl_source/saixian_osd_overlay.v',str(reference)],check=True)
    subprocess.run(['C:/iverilog/bin/vvp.exe',str(exe)],check=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--work',type=Path,required=True)
    run(p.parse_args().work)
