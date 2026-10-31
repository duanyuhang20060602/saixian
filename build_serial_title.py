from pathlib import Path
import sys,os
sys.path.insert(0,str(Path('5.0project/tools').resolve()))
from build_v4_port import build
b=sys.argv[1]
os.environ['SAIXIAN_TEMP_ROOT']=str(Path('temp-serial-title-'+b).resolve())
os.environ['SAIXIAN_PLACE_SEED']=sys.argv[3] if len(sys.argv)>3 else '7'
if b=='b':os.environ['SAIXIAN_PHYSICAL_STRATEGY']='TimingUltraEmbeddedCompactMacroGuardAll'
build(b,Path(sys.argv[2]).resolve())
