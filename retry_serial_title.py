from pathlib import Path
import json,os,sys
sys.path.insert(0,str(Path('5.0project/tools').resolve()))
from build_v4_port import build
board,origin,seed,out=sys.argv[1:5];r=json.loads(Path(origin,f'builds/board_{board}/result.json').read_text());os.environ['SAIXIAN_PLACE_SEED']=seed;os.environ['SAIXIAN_TEMP_ROOT']=str(Path('temp-serial-retry-'+board+seed).resolve())
if r.get('physical_strategy'):os.environ['SAIXIAN_PHYSICAL_STRATEGY']=r['physical_strategy']['name']
if r.get('synthesis_strategy'):os.environ['SAIXIAN_SYNTHESIS_STRATEGY']=r['synthesis_strategy']['name']
build(board,Path(out).resolve(),Path(origin).resolve())
