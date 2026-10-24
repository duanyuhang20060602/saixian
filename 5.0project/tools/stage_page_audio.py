"""Stage only a verified A/B pair matching current sources and regression hashes."""
from pathlib import Path
import argparse, hashlib, json, shutil, zipfile, subprocess
from build_v4_port import inputs
from test_page_audio import JOBS as PAGE_TESTS
from test_touchscreen import JOBS as TOUCH_TESTS

ROOT=Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--a-build',type=Path,required=True)
    parser.add_argument('--b-build',type=Path,required=True)
    parser.add_argument('--destination',type=Path,default=ROOT/'delivery_page_audio_interval')
    args=parser.parse_args()
    records=[]
    tests=[]
    for directory,expected in [('touchscreen_results',TOUCH_TESTS),('page_audio_results',PAGE_TESTS)]:
        entries=json.loads((ROOT/'tests'/directory/'results.json').read_text(encoding='utf-8'))
        assert {r['test'] for r in entries}==set(expected),'Incomplete regression set'
        for entry in entries:
            assert entry['passed'] and all(sha(ROOT/p)==h for p,h in entry['inputs_sha256'].items()),'Stale/failed regression: '+entry['test']
        tests+=entries
    for board,base in [('a',args.a_build),('b',args.b_build)]:
        record=json.loads((base/f'builds/board_{board}/result.json').read_text())
        assert record['status']=='passed' and record['inputs_unchanged'] and record['toolchain_unchanged'],'Build did not pass'
        assert record['inputs_sha256']==inputs('board_'+board),'Build differs from current sources'
        assert sha(record['bit']['path'])==record['bit']['sha256'],'Bitstream changed'
        records.append(record)
    out=args.destination.resolve()
    out.mkdir(exist_ok=False)
    artifacts={}
    for record in records:
        board=record['board'].upper()
        filename=f'PHOTO_BOARD_{board}_PAGE_CUE_INTERVAL.bit'
        shutil.copy2(record['bit']['path'],out/filename)
        artifacts[filename]=sha(out/filename)
        (out/f'board_{board.lower()}_build.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
        for report in ['area','timing']:
            source=Path(record[report]['path'])
            shutil.copy2(source,out/source.name)
    shutil.copy2(ROOT/'PAGE_AUDIO_INTERVAL.md',out/'README.md')
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    manifest={'baseline':'ac0370e','source_commit':commit,'hardware_validation':'pending','boards':records,'tests':tests,'files_sha256':artifacts}
    (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    archive=out/'SAIXIAN_PAGE_CUE_INTERVAL_AB.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as package:
        for p in out.iterdir():
            if p!=archive:package.write(p,p.name)
    print(str(archive))

if __name__=='__main__':main()
