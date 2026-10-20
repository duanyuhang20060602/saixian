"""Read-only integrity and TD path check for the saved 5.0 project."""
from pathlib import Path
import argparse,hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def verify(strict=True):
    record=json.loads((ROOT/'package_manifest.json').read_text(encoding='utf-8'))
    for relative,expected in (record['files_sha256'].items() if strict else ()):
        path=(ROOT/relative).resolve()
        assert path.is_relative_to(ROOT) and path.is_file(),relative
        assert digest(path)==expected,'Saved file changed: '+relative
    boards={}
    for board in ('a','b'):
        td=ROOT/f'src/board_{board}/td_project';name='PHOTO_BOARD_'+board.upper()
        text=(td/(name+'.al')).read_text(encoding='utf-8-sig')
        source_section=re.search(r'<Source_Files>(.*?)</Source_Files>',text,re.S)
        paths=re.findall(r'<File Path="([^"]+)"',source_section[1])
        assert paths==json.loads((td/'sources.json').read_text(encoding="utf-8-sig")),'AL/source-list mismatch'
        for relative in paths:
            p=(td/relative).resolve();assert p.is_relative_to(ROOT) and p.is_file(),relative
        flow=(td/'build_board.tcl').read_text(encoding="utf-8-sig")
        for relative in re.findall(r'\.\./user_source/[A-Za-z0-9_./-]+',flow):assert (td/relative).is_file(),relative
        assert (td/'../user_source/hdl_source/include/global_def.v').is_file()
        saved=ROOT/f'releases/PHOTO_BOARD_{board.upper()}_5_0.bit'
        if strict:assert digest(td/(name+'.bit'))==digest(saved)==record['release_files'][saved.relative_to(ROOT).as_posix()]
        boards[board]={'project':str(td/(name+'.al')),'source_count':len(paths),'bit_sha256':digest(saved)}
    origin=json.loads((ROOT/'releases/origin_validation.json').read_text(encoding="utf-8-sig"))
    if strict:
        assert origin['test_count']==65 and all(r['passed'] for rs in origin['tests'].values() for r in rs)
        assert digest(ROOT/'examples/TF卡素材/AWARD720.DLT')==digest(ROOT/'award_media/AWARD720.DLT')==origin['files_sha256']['AWARD720.DLT']
    if strict:
        assert not any(p.suffix.lower() in ('.md','.zip') for p in ROOT.rglob('*') if p.is_file())
    return {'passed':True,'saved_files_checked':len(record['files_sha256']),'saved_rtl_files':record['saved_rtl_files'],
            'boards':boards,'origin_test_count':65,'origin_hardware_validation':origin['hardware_validation'],
            'scope':'File integrity, exact firmware/media hashes, preserved RTL behavior and independent TD input paths; no FPGA rebuild performed.'}
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--report',type=Path);args=parser.parse_args()
    result=verify()
    if args.report:args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
