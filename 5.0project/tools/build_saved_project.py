"""Build saved A/B sources in E:/Codex/Work; retain the frozen release."""
from pathlib import Path
import argparse,datetime,json,os,re,shutil
from build_v4_port import ROOT,build,digest,inputs
from verify_saved_project import verify
from prepare_compact_menu import verify as verify_compact_menu
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--board',choices=('a','b','both'),default='both')
    parser.add_argument('--work',type=Path);parser.add_argument('--td-root',type=Path)
    parser.add_argument('--verify-only',action='store_true');args=parser.parse_args()
    # Integrity verification checks the frozen snapshot; ordinary rebuilds
    # validate current paths and permit intentional source-code changes.
    verify(strict=args.verify_only)
    verify_compact_menu()
    if args.board in ('a','both'):
        from prepare_menu_edge_rom import verify as verify_packed_rom
        verify_packed_rom()
    if args.verify_only:print('PASS saved project verification');return
    stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    work=args.work or Path('E:/Codex/Work')/((json.loads((ROOT/'package_manifest.json').read_text(encoding='utf-8'))['version']+'project-build-'+stamp))
    explicit_guard=os.environ.get('SAIXIAN_SETUP_GUARD_NS')
    explicit_seed=os.environ.get('SAIXIAN_PLACE_SEED')
    explicit_strategy=os.environ.get('SAIXIAN_PHYSICAL_STRATEGY')
    explicit_synthesis=os.environ.get('SAIXIAN_SYNTHESIS_STRATEGY')
    explicit_route_effort=os.environ.get('SAIXIAN_ROUTE_EFFORT')
    explicit_route_swap=os.environ.get('SAIXIAN_ROUTE_SWAP_PIN')
    manifest=json.loads((ROOT/'package_manifest.json').read_text(encoding='utf-8'))
    profiles={r['board']:r for r in manifest.get('release_builds',[])}
    if args.td_root:os.environ['SAIXIAN_TD_ROOT']=args.td_root.as_posix()
    records=[]
    for board in (('a','b') if args.board=='both' else (args.board,)):
        profile=profiles.get(board,{})
        accepted=json.loads((ROOT/profile['record']).read_text(encoding='utf-8')) if profile.get('record') else {}
        os.environ['SAIXIAN_SETUP_GUARD_NS']=explicit_guard or str(accepted.get('optimization_guard',{}).get('setup_margin_ns',0.20))
        # Reproduce each accepted board's placement recipe, while retaining
        # explicit user overrides for source-development experiments.
        os.environ['SAIXIAN_PLACE_SEED']=explicit_seed or accepted.get('place_seed_override') or ('17' if board=='a' else '11')
        os.environ['SAIXIAN_PHYSICAL_STRATEGY']=explicit_strategy or accepted.get('physical_strategy',{}).get('name','TimingUltraEmbedded')
        route_params={p['param']:p['val'] for p in accepted.get('physical_strategy',{}).get('parameters',[]) if p['step']=='route'}
        saved_default_effort=bool(accepted) and 'effort' not in route_params
        route_effort=explicit_route_effort or ('default' if saved_default_effort and not explicit_strategy else None)
        route_swap=explicit_route_swap or ('on' if route_params.get('swap_pin')=='on' and not explicit_strategy else None)
        if route_effort:os.environ['SAIXIAN_ROUTE_EFFORT']=route_effort
        else:os.environ.pop('SAIXIAN_ROUTE_EFFORT',None)
        if route_swap:os.environ['SAIXIAN_ROUTE_SWAP_PIN']=route_swap
        else:os.environ.pop('SAIXIAN_ROUTE_SWAP_PIN',None)
        synthesis=explicit_synthesis or accepted.get('synthesis_strategy',{}).get('name')
        if synthesis:os.environ['SAIXIAN_SYNTHESIS_STRATEGY']=synthesis
        else:os.environ.pop('SAIXIAN_SYNTHESIS_STRATEGY',None)
        build(board,work)
        record=json.loads((work/f'builds/board_{board}/result.json').read_text(encoding="utf-8-sig"))
        log=(work/f'builds/board_{board}/build.log').read_text(errors='replace')
        slices=re.findall(r'PHY-1001 : (\d+) mslices,',log)
        assert record['status']=='passed' and record['inputs_sha256']==inputs('board_'+board)
        assert slices and int(slices[-1])<=4900
        records.append(record)
    destination=work/'release';destination.mkdir(parents=True,exist_ok=False)
    files={}
    for record in records:
        board=record['board'];name='PHOTO_BOARD_'+board.upper()+'_'+manifest['version'].replace('.','_')+'.bit'
        shutil.copy2(record['bit']['path'],destination/name);files[name]=digest(destination/name)
        for kind in ('timing','area'):shutil.copy2(record[kind]['path'],destination/Path(record[kind]['path']).name)
    (destination/'validation.json').write_text(json.dumps({'hardware_validation':'pending','boards':records,'files_sha256':files},indent=2)+'\n',encoding='utf-8')
    print('Passed rebuild: '+str(destination))
if __name__=='__main__':main()
