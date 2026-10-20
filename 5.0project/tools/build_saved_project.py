"""Build saved A/B sources in E:/Codex/Work; retain the frozen release."""
from pathlib import Path
import argparse,datetime,json,os,re,shutil
from build_v4_port import ROOT,build,digest,inputs
from verify_saved_project import verify
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--board',choices=('a','b','both'),default='both')
    parser.add_argument('--work',type=Path);parser.add_argument('--td-root',type=Path)
    parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    # Integrity verification checks the frozen snapshot; ordinary rebuilds
    # validate current paths and permit intentional source-code changes.
    verify(strict=args.verify_only)
    if args.verify_only:print('PASS saved project verification');return
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    work=args.work or Path('E:/Codex/Work')/('5.0project-build-'+stamp)
    os.environ.setdefault('SAIXIAN_PLACE_SEED','19')
    os.environ.setdefault('SAIXIAN_PHYSICAL_STRATEGY','TimingUltraEmbedded')
    if args.td_root:os.environ['SAIXIAN_TD_ROOT']=args.td_root.as_posix()
    records=[]
    for board in (('a','b') if args.board=='both' else (args.board,)):
        build(board,work)
        record=json.loads((work/f'builds/board_{board}/result.json').read_text(encoding="utf-8-sig"))
        log=(work/f'builds/board_{board}/build.log').read_text(errors='replace')
        slices=re.findall(r'PHY-1001 : (\d+) mslices,',log)
        assert record['status']=='passed' and record['inputs_sha256']==inputs('board_'+board)
        assert slices and int(slices[-1])<=4900
        records.append(record)
    destination=ROOT/'releases'/('rebuild_'+stamp);destination.mkdir(parents=True,exist_ok=False)
    files={}
    for record in records:
        board=record['board'];name='PHOTO_BOARD_'+board.upper()+'_5_0.bit'
        shutil.copy2(record['bit']['path'],destination/name);files[name]=digest(destination/name)
        for kind in ('timing','area'):shutil.copy2(record[kind]['path'],destination/Path(record[kind]['path']).name)
    (destination/'validation.json').write_text(json.dumps({'hardware_validation':'pending','boards':records,'files_sha256':files},indent=2)+'\n',encoding='utf-8')
    print('Passed rebuild: '+str(destination))
if __name__=='__main__':main()
