"""Build the selected V4 ports in an isolated E-drive workspace.

Existing FLUID_SMOOTH deliveries are never overwritten. A matched pair is
staged only after both fresh builds and current regression inputs pass.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORK = Path('E:/Codex/Work/cooperate-v4-port-20261018')
LIMITS = {'lut': 19600, 'reg': 19600, 'bram': 64, 'bram32k': 16, 'dsp': 29}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inputs(role):
    td = ROOT/f'src/{role}/td_project'
    paths = [(td/p).resolve() for p in json.loads((td/'sources.json').read_text())]
    source_xml = re.search(r'<Source_Files>(.*?)</Source_Files>',
                           (td/('PHOTO_'+role.upper()+'.al')).read_text(encoding='utf-8-sig'), re.S)
    assert source_xml, 'Missing TD source list: '+role
    declared = {(td/p.replace('\\','/')).resolve() for p in
                re.findall(r'<File Path="([^"]+)"', source_xml[1])}
    assert declared == set(paths), 'TD .al source list differs from sources.json: '+role
    paths += [td/'sources.json', td/'build_board.tcl', td/('PHOTO_'+role.upper()+'.al')]
    paths += list((td.parent/'user_source/constraints_source').glob('*'))
    paths += list((td.parent/'user_source/hdl_source').rglob('*.mif'))
    paths += list((td.parent/'user_source/hdl_source/IP').glob('*.tcl'))
    paths += list((td.parent/'user_source/hdl_source/include').glob('*'))
    paths += list((ROOT/'common').rglob('*.mif'))
    paths += list((ROOT/'common').rglob('*.hex'))
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(set(paths)) if p.is_file()}

def build(board, work, mapped_from=None):
    role = 'board_'+board
    out = work/'builds'/role
    project = out/'project'
    if project.exists():
        raise SystemExit('Use a fresh --work directory for another build: '+str(project))
    out.mkdir(parents=True, exist_ok=True)
    before = inputs(role)
    started = time.time()
    record = {'board': board, 'status': 'running', 'hardware_validation': 'pending',
              'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'inputs_sha256': before, 'work_project': str(project)}
    (out/'result.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    ignored = shutil.ignore_patterns('*_Runs', '*.bit', '*.db', '*.log', '*.logw', '*.area',
                                     '*.timing', '*.rpt', '*.ts', '*.bid', '*.qor', '*.dmp', '.lock*')
    shutil.copytree(ROOT/'common', project/'common', ignore=ignored)
    shutil.copytree(ROOT/'src', project/'src', ignore=ignored)
    td = project/f'src/{role}/td_project'
    name = 'PHOTO_'+role.upper()
    al = td/(name+'.al')
    text = al.read_text(encoding='utf-8-sig')
    text, count = re.subn(r'(<Project\b[^>]*\bPath=")[^"]*(")',
                         lambda match: match[1]+td.as_posix()+match[2], text, count=1)
    assert count == 1
    al.write_text(text, encoding='utf-8', newline='\n')
    record['local_project_sha256'] = digest(al)
    # ROM readers normally resolve relative to their source file. Also make
    # basename-only IP initialization references available in the build cwd.
    for mif in [*(project/'common').rglob('*.mif'), *(project/'common').rglob('*.hex'), *(td.parent/'user_source').rglob('*.mif')]:
        destination = td/mif.name
        if destination.exists() and digest(destination) != digest(mif):
            raise SystemExit('Conflicting ROM basename: '+mif.name)
        shutil.copy2(mif, destination)
    # V4's verified mapped-checkpoint retry: only placement/routing changes.
    # Never reuse a mapping whose source, constraints or toolchain changed.
    origin = None
    if mapped_from:
        origin_path = mapped_from/f'builds/{role}/result.json'
        origin = json.loads(origin_path.read_text())
        assert origin['inputs_unchanged'] and origin['toolchain_unchanged']
        assert origin['inputs_sha256'] == before, 'Mapped source/constraints are stale'
        checkpoint = Path(origin['work_project'])/f'src/{role}/td_project'/f'{name}_gate.db'
        record['mapped_origin'] = {'result': str(origin_path), 'result_sha256': digest(origin_path),
                                   'checkpoint': str(checkpoint), 'checkpoint_sha256': digest(checkpoint)}
        shutil.copy2(checkpoint, td/checkpoint.name)
        flow = td/'build_board.tcl'
        recipe = flow.read_text(encoding='utf-8')
        assert recipe.count('set start_step read_design') == 1
        recipe = recipe.replace('set start_step read_design', 'set parent .\nset start_step opt_place')
        flow.write_text(recipe, encoding='utf-8', newline='\n')
        record['local_physical_recipe_sha256'] = digest(flow)
    environment = os.environ.copy()
    if not environment.get('SAIXIAN_PLACE_SEED'):
        environment['SAIXIAN_PLACE_SEED'] = '19' if board == 'b' else '17'
    record['place_seed_override'] = environment.get('SAIXIAN_PLACE_SEED')
    temp = Path('E:/Codex/Temp/cooperate-v4-port')
    temp.mkdir(parents=True, exist_ok=True)
    environment.update(TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp))
    td_root = Path(environment.get('SAIXIAN_TD_ROOT', 'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116'))
    tool = td_root/'bin/td_commands_prompt.exe'
    environment['SAIXIAN_TD_ROOT'] = td_root.as_posix()
    physical_strategy = environment.get('SAIXIAN_PHYSICAL_STRATEGY')
    if physical_strategy:
        catalog = td_root/'doc/strategies/official_strategy_ph1.json'
        strategies = json.loads(catalog.read_text(encoding='utf-8'))
        strategy_base = {'MacroTimingExtra':'MacroTiming','TimingUltraNoPadSplit':'TimingUltra','TimingUltraEmbedded':'TimingUltra'}.get(physical_strategy,physical_strategy)
        strategy = dict(strategies[strategy_base])
        strategy['params'] = list(strategy['params'])
        if physical_strategy in ('TimingUltraNoPadSplit','TimingUltraEmbedded'):
            strategy['params'] += [{'step':'place','param':'split_data_from_clock','val':'off'}]
        if physical_strategy == 'TimingUltraEmbedded':
            # The post-place crit_path_opt zigzag pass queries external-pad
            # coordinates on embedded SDRAM pads (ARC-8011/PHY-8105).
            strategy['params'] += [{'step':'place','param':'crit_path_opt','val':'off'},
                                   {'step':'place','param':'aggressive_opt','val':'20'}]
        if physical_strategy == 'MacroTimingExtra':
            strategy['params'] += [p for p in strategies['TimingUltra']['params'] if p['param']=='postrt_opt_extra_round']
        assert strategy['is_syn'] == 'phy', 'Only physical strategy overrides may reuse mapping'
        assert all(p['step'] in ('place', 'route') for p in strategy['params'])
        flow = td/'build_board.tcl'
        recipe = flow.read_text(encoding='utf-8')
        marker = 'set tdRoot '
        pos = recipe.index(marker)
        overrides = ''.join('lappend phyWildParams {'+p['step']+'} {'+p['param']+'} {'+p['val']+'}\n'
                            for p in strategy['params'])
        recipe = recipe[:pos]+overrides+recipe[pos:]
        flow.write_text(recipe, encoding='utf-8', newline='\n')
        record['physical_strategy'] = {'name': physical_strategy, 'base': strategy_base, 'catalog': str(catalog),
                                       'catalog_sha256': digest(catalog), 'parameters': strategy['params']}
        record['local_physical_recipe_sha256'] = digest(flow)
    synthesis_strategy = environment.get('SAIXIAN_SYNTHESIS_STRATEGY')
    if mapped_from:
        if synthesis_strategy:
            assert origin.get('synthesis_strategy', {}).get('name') == synthesis_strategy, 'Cannot change synthesis while reusing mapping'
        if origin.get('synthesis_strategy'):
            record['synthesis_strategy'] = origin['synthesis_strategy']
            assert digest(Path(record['synthesis_strategy']['catalog'])) == record['synthesis_strategy']['catalog_sha256']
    elif synthesis_strategy:
        catalog = td_root/'doc/strategies/official_strategy_ph1.json'
        strategy = json.loads(catalog.read_text(encoding='utf-8'))[synthesis_strategy]
        assert strategy['is_syn'] == 'syn'
        assert all(p['step'] in ('rtl', 'gate') for p in strategy['params'])
        flow = td/'build_board.tcl'
        recipe = flow.read_text(encoding='utf-8')
        position = recipe.index('set tdRoot ')
        parameters = ''.join('lappend phyWildParams {'+p['step']+'} {'+p['param']+'} {'+p['val']+'}\n' for p in strategy['params'])
        flow.write_text(recipe[:position]+parameters+recipe[position:], encoding='utf-8', newline='\n')
        record['synthesis_strategy'] = {'name': synthesis_strategy, 'catalog': str(catalog),
                                      'catalog_sha256': digest(catalog), 'parameters': strategy['params']}
        record['local_physical_recipe_sha256'] = digest(flow)
    tool_files = [tool, *(td_root/'doc/scripts').glob('*.tcl')]
    tool_hashes = {str(p): digest(p) for p in tool_files}
    if origin:
        assert origin['toolchain_sha256'] == tool_hashes, 'Mapped toolchain changed'
    record['toolchain_sha256'] = tool_hashes
    # Persist the full provenance before TD starts so an interrupted run can
    # retain its source/tool fingerprints and mapped checkpoint information.
    (out/'result.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    with (out/'build.log').open('w', encoding='utf-8') as log:
        run = subprocess.run([str(tool), 'build_board.tcl'], cwd=td, env=environment,
                             stdout=log, stderr=subprocess.STDOUT)
    record.update(returncode=run.returncode, seconds=round(time.time()-started, 1),
                  inputs_unchanged=before == inputs(role),
                  toolchain_unchanged=all(digest(Path(p)) == h for p, h in tool_hashes.items()))
    if mapped_from:
        record['mapped_origin_unchanged'] = digest(checkpoint) == record['mapped_origin']['checkpoint_sha256']
    timing = td/(name+'_pr.timing')
    area = td/(name+'_phy.area')
    bit = td/(name+'.bit')
    timing_text = timing.read_text(errors='replace') if timing.exists() else ''
    area_text = area.read_text(errors='replace') if area.exists() else ''
    values = {key: float(value) for key, value in re.findall(
        r'(SWNS|STNS|HWNS|HTNS):\s*(-?[0-9.]+)ns', timing_text)}
    usage = {key: int(value) for key, value in re.findall(
        r'(?m)^\s*#(lut|reg|bram|bram32k|dsp)\s+(\d+)\b', area_text)}
    record.update(timing_ns=values, resources=usage)
    fresh = all(p.exists() and p.stat().st_mtime >= started for p in (bit, timing, area))
    log_text = (out/'build.log').read_text(errors='replace')
    clean_log = not re.search(r'(?im)^.*(?:ERROR:|ERROR \[)', log_text)
    passed = (run.returncode == 0 and fresh and clean_log and record['inputs_unchanged']
              and record['toolchain_unchanged'] and record.get('mapped_origin_unchanged', True) and len(values) == 4
              and values['SWNS'] >= 0 and values['HWNS'] >= 0
              and values['STNS'] == 0 and values['HTNS'] == 0
              and all(k in usage and usage[k] <= v for k, v in LIMITS.items()))
    for kind, path in [('bit', bit), ('timing', timing), ('area', area)]:
        if path.exists():
            record[kind] = {'path': str(path), 'sha256': digest(path)}
            if kind != 'bit':
                shutil.copy2(path, out/path.name)
    record['status'] = 'passed' if passed else 'failed'
    (out/'result.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: record[k] for k in ['board', 'status', 'seconds', 'timing_ns', 'resources']}, indent=2), flush=True)
    if not passed:
        raise SystemExit(1)

def stage(work, b_work=None):
    records = [json.loads((base/f'builds/board_{b}/result.json').read_text())
               for b, base in [('a', work), ('b', b_work or work)]]
    tests = json.loads((work/'tests/results.json').read_text())
    from test_v4_port import JOBS
    assert set(JOBS) == {test['test'] for test in tests}, 'Incomplete regression set'
    for test in tests:
        assert test['passed'] and all(digest(ROOT/p) == h for p, h in test['inputs_sha256'].items()), 'Stale/failed test'
    for record in records:
        assert record['status'] == 'passed' and record['inputs_sha256'] == inputs('board_'+record['board']), 'Stale/failed build'
        assert digest(Path(record['bit']['path'])) == record['bit']['sha256']
    destination = ROOT/'delivery/v4_port_20261018'
    destination.mkdir(parents=True, exist_ok=False)
    artifacts = {}
    for record in records:
        role = 'board_'+record['board']
        filename = 'PHOTO_BOARD_'+record['board'].upper()+'_720P_V3_1_V4_PORT.bit'
        shutil.copy2(record['bit']['path'], destination/filename)
        artifacts[filename] = digest(destination/filename)
        (destination/(role+'_build.json')).write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
        for report in [Path(record['timing']['path']), Path(record['area']['path'])]:
            shutil.copy2(report, destination/report.name)
    shutil.copy2(work/'tests/results.json', destination/'validation.json')
    shutil.copy2(ROOT/'V4_PORT_INTEGRATION.md', destination/'README.md')
    manifest = {'baseline_commit': '7800f11e75ae5ad1c8ce759986c77648aeb68277',
                'version': 'FLUID_SMOOTH + selected V4 optimizations',
                'hardware_validation': 'pending', 'files_sha256': artifacts,
                'boards': records, 'tests': tests}
    (destination/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    archive = destination/'V4_PORT_AB_20261018.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
        for path in destination.iterdir():
            if path != archive:
                package.write(path, path.name)
    print('Staged matched pair: '+str(archive), flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['a', 'b', 'stage'])
    parser.add_argument('--work', type=Path, default=DEFAULT_WORK)
    parser.add_argument('--b-work', type=Path, help='Use a separately recorded B layout retry when staging')
    parser.add_argument('--mapped-from', type=Path, help='Reuse a verified identical mapped checkpoint for a physical-only retry')
    args = parser.parse_args()
    if args.action == 'stage':
        stage(args.work.resolve(), args.b_work.resolve() if args.b_work else None)
    else:
        build(args.action, args.work.resolve(), args.mapped_from.resolve() if args.mapped_from else None)
