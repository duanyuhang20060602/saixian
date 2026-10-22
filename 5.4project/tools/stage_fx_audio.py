"""Stage a matched, timing-clean pair with exact current source/test fingerprints."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,zipfile
from build_v4_port import inputs
from test_fx_audio import JOBS as FX_TESTS
from test_touchscreen import JOBS as TOUCH_TESTS

ROOT=Path(__file__).resolve().parents[1]

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--a-build',type=Path,required=True)
    parser.add_argument('--b-build',type=Path,required=True)
    parser.add_argument('--destination',type=Path,default=ROOT/'delivery_fx_page_audio')
    args=parser.parse_args()
    tests=[];records=[]
    for directory,jobs in [('touchscreen_results',TOUCH_TESTS),('fx_audio_results',FX_TESTS)]:
        entries=json.loads((ROOT/'tests'/directory/'results.json').read_text(encoding='utf-8'))
        assert {r['test'] for r in entries}==set(jobs),'Incomplete regression set'
        for r in entries:
            assert r['passed'] and all(sha(ROOT/p)==h for p,h in r['inputs_sha256'].items()),'Failed/stale regression: '+r['test']
        tests+=entries
    for board,base in [('a',args.a_build),('b',args.b_build)]:
        r=json.loads((base/f'builds/board_{board}/result.json').read_text())
        assert r['status']=='passed' and r['inputs_unchanged'] and r['toolchain_unchanged']
        assert r['inputs_sha256']==inputs('board_'+board),'Build inputs are stale'
        assert sha(r['bit']['path'])==r['bit']['sha256']
        records.append(r)
    out=args.destination.resolve();out.mkdir(exist_ok=False)
    artifacts={}
    for r in records:
        filename=f"PHOTO_BOARD_{r['board'].upper()}_FX_PAGE_AUDIO.bit"
        shutil.copy2(r['bit']['path'],out/filename);artifacts[filename]=sha(out/filename)
        (out/f"board_{r['board']}_build.json").write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
        for kind in ['area','timing']:
            source=Path(r[kind]['path']);shutil.copy2(source,out/source.name)
    shutil.copy2(ROOT/'FX_PAGE_AUDIO.md',out/'README.md')
    shutil.copy2(ROOT/'RESOURCE_REPORT_FX_PAGE_AUDIO.md',out/'RESOURCE_REPORT_FX_PAGE_AUDIO.md')
    shutil.copy2(ROOT/'tests/fx_audio_results/placement_summary.json',out/'placement_summary.json')
    commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    (out/'manifest.json').write_text(json.dumps({'source_commit':commit,'baseline':'af1fe0b','hardware_validation':'pending','boards':records,'tests':tests,'files_sha256':artifacts},indent=2)+'\n',encoding='utf-8')
    archive=out/'SAIXIAN_FX_PAGE_AUDIO_AB.zip'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for p in out.iterdir():
            if p!=archive:z.write(p,p.name)
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for name,digest in artifacts.items():assert hashlib.sha256(z.read(name)).hexdigest()==digest
    print(archive)

if __name__=='__main__':main()
