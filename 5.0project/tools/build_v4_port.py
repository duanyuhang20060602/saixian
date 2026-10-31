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
    paths += list((ROOT/'common').rglob('*.vh'))
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in sorted(set(paths)) if p.is_file()}

def build(board, work, mapped_from=None, checkpoint_stage='gate'):
    assert checkpoint_stage in ('gate', 'place','pr')
    assert mapped_from or checkpoint_stage == 'gate'
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
    for mif in [*(project/'common').rglob('*.mif'), *(project/'common').rglob('*.hex'), *(project/'common').rglob('*.vh'), *(td.parent/'user_source').rglob('*.mif')]:
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
        checkpoint = Path(origin['work_project'])/f'src/{role}/td_project'/f'{name}_{checkpoint_stage}.db'
        record['mapped_origin'] = {'result': str(origin_path), 'result_sha256': digest(origin_path),
                                   'checkpoint': str(checkpoint), 'checkpoint_sha256': digest(checkpoint),
                                   'checkpoint_stage': checkpoint_stage}
        shutil.copy2(checkpoint, td/(name+'_place.db' if checkpoint_stage=='pr' else checkpoint.name))
        flow = td/'build_board.tcl'
        recipe = flow.read_text(encoding='utf-8')
        assert recipe.count('set start_step read_design') == 1
        next_step = 'opt_place' if checkpoint_stage == 'gate' else 'opt_route'
        recipe = recipe.replace('set start_step read_design', 'set parent .\nset start_step '+next_step)
        flow.write_text(recipe, encoding='utf-8', newline='\n')
        record['local_physical_recipe_sha256'] = digest(flow)
    environment = os.environ.copy()
    if not environment.get('SAIXIAN_PLACE_SEED'):
        environment['SAIXIAN_PLACE_SEED'] = '19' if board == 'b' else '17'
    record['place_seed_override'] = environment.get('SAIXIAN_PLACE_SEED')
    temp = Path(os.environ.get('SAIXIAN_TEMP_ROOT', 'E:/Codex/Temp/cooperate-v4-port'))
    temp.mkdir(parents=True, exist_ok=True)
    environment.update(TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp))
    td_root = Path(environment.get('SAIXIAN_TD_ROOT', 'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116'))
    tool = td_root/'bin/td_commands_prompt.exe'
    environment['SAIXIAN_TD_ROOT'] = td_root.as_posix()
    physical_strategy = environment.get('SAIXIAN_PHYSICAL_STRATEGY')
    requested_physical_strategy = physical_strategy
    macro_extra = physical_strategy == 'TimingUltraEmbeddedCompactMacroExtraRoute'
    clean_guard = physical_strategy == 'MacroTimingEmbeddedCleanGuardAll'
    guard_route = physical_strategy in ('TimingUltraEmbeddedCompactMacroGuardRoute','TimingUltraEmbeddedCompactMacroGuardAll','MacroTimingEmbeddedCleanGuardAll')
    guard_place = physical_strategy in ('TimingUltraEmbeddedCompactMacroGuardAll','MacroTimingEmbeddedCleanGuardAll')
    if clean_guard:
        physical_strategy = 'MacroTimingEmbeddedCleanRoute'
    compact_macro = physical_strategy in ('TimingUltraEmbeddedCompactMacroRoute','TimingUltraEmbeddedCompactMacroExtraRoute','TimingUltraEmbeddedCompactMacroGuardRoute','TimingUltraEmbeddedCompactMacroGuardAll')
    if compact_macro:
        physical_strategy = 'TimingUltraEmbeddedCompactRoute'
    if mapped_from and checkpoint_stage in ('place','pr'):
        assert physical_strategy, 'Placed retry requires an explicit routing profile'
    if physical_strategy:
        catalog = td_root/'doc/strategies/official_strategy_ph1.json'
        strategies = json.loads(catalog.read_text(encoding='utf-8'))
        strategy_base = {'TimingUltraEmbeddedCompactRoute':'TimingUltra','MacroTimingEmbeddedCleanRoute':'MacroTiming','MacroTimingExtra':'MacroTiming','MacroTimingEmbedded':'MacroTiming','TimingUltraEmbeddedCleanRoute':'TimingUltra','TimingUltraNoPadSplit':'TimingUltra','TimingUltraEmbedded':'TimingUltra','TimingUltraEmbeddedExtra':'TimingUltra','TimingUltraEmbeddedNoSwap':'TimingUltra','TimingMediumEmbedded':'TimingMedium','TimingMediumEmbeddedReset':'TimingMedium','CongestionEmbedded':'CongestionHigh'}.get(physical_strategy,physical_strategy)
        strategy = dict(strategies[strategy_base])
        strategy['params'] = list(strategy['params'])
        if physical_strategy in ('TimingUltraEmbeddedCompactRoute','TimingUltraEmbeddedCleanRoute','TimingUltraNoPadSplit','TimingUltraEmbedded','TimingUltraEmbeddedExtra','TimingUltraEmbeddedNoSwap','TimingMediumEmbedded','TimingMediumEmbeddedReset','MacroTimingEmbedded','MacroTimingEmbeddedCleanRoute','CongestionEmbedded'):
            strategy['params'] += [{'step':'place','param':'split_data_from_clock','val':'off'}]
        if physical_strategy in ('TimingUltraEmbeddedCompactRoute','TimingUltraEmbeddedCleanRoute','TimingUltraEmbedded','TimingUltraEmbeddedExtra','TimingUltraEmbeddedNoSwap','TimingMediumEmbedded','TimingMediumEmbeddedReset','MacroTimingEmbedded','MacroTimingEmbeddedCleanRoute','CongestionEmbedded'):
            # The post-place crit_path_opt zigzag pass queries external-pad
            # coordinates on embedded SDRAM pads (ARC-8011/PHY-8105).
            strategy['params'] += [{'step':'place','param':'crit_path_opt','val':'off'},
                                   {'step':'place','param':'aggressive_opt','val':'20'}]
        if physical_strategy == 'MacroTimingExtra':
            strategy['params'] += [p for p in strategies['TimingUltra']['params'] if p['param']=='postrt_opt_extra_round']
        if physical_strategy in ('CongestionEmbedded','MacroTimingEmbedded','TimingMediumEmbedded','TimingMediumEmbeddedReset'):
            strategy['params'] += [p for p in strategies['TimingUltra']['params'] if p['param']=='postrt_opt_extra_round']
        if physical_strategy in ('TimingUltraEmbeddedExtra', 'TimingUltraEmbeddedNoSwap'):
            strategy['params'] += [{'step':'route','param':'postrt_opt_extra_round','val':'8'}]
        if physical_strategy == 'TimingUltraEmbeddedNoSwap':
            strategy['params'] += [{'step':'route','param':'swap_pin','val':'off'}]
        if physical_strategy in ('TimingUltraEmbeddedCleanRoute','TimingUltraEmbeddedCompactRoute','MacroTimingEmbeddedCleanRoute'):
            # Preserve placement/timing checks; avoid the tool's failing
            # post-route ECO reconstruction and maximize route cleanup.
            strategy['params'] += [{'step':'route','param':'post_route_opt','val':'off'},
                                   {'step':'route','param':'postrt_opt_extra_round','val':'0'},
                                   {'step':'route','param':'effort','val':'routability'},
                                   {'step':'route','param':'swap_pin','val':'off'}]
        if physical_strategy == 'TimingUltraEmbeddedCompactRoute':
            # Keep mapping and clocks intact. Avoid area-expanding prepack
            # logic-level restructuring when the device is nearly full.
            strategy['params'] += [{'step':'place','param':'aggressive_opt','val':'0'},
                                   {'step':'place','param':'logic_level_opt','val':'off'},
                                   {'step':'place','param':'hfn_opt_effort','val':'low'}]
        if compact_macro:
            # Keep the compact packing recipe while prioritizing RAM/DSP nets.
            # These are the documented MacroTiming placement parameters.
            strategy['params'] += [{'step':'place','param':'enlarge_macro_net_weight','val':'on'},
                                   {'step':'place','param':'mcflg_eram_anchor_driven','val':'medium'},
                                   {'step':'place','param':'macro_performance','val':'macro_congestion'}]
        if macro_extra:
            # Same compact macro placement, with documented timing cleanup
            # for B's remaining sub-nanosecond routed setup paths.
            strategy['params'] += [{'step':'route','param':'post_route_opt','val':'high'},
                                   {'step':'route','param':'postrt_opt_extra_round','val':'4'}]
        if environment.get('SAIXIAN_ROUTE_POST_OPT')=='high':
            strategy['params'] += [{'step':'route','param':'post_route_opt','val':'high'},
                                   {'step':'route','param':'postrt_opt_extra_round','val':'4'}]
        if clean_guard:
            # B has spare logic area. Explicitly re-enable restructuring
            # instead of inheriting the compact gate checkpoint's settings.
            strategy['params'] += [{'step':'place','param':'logic_level_opt','val':'on'},
                                   {'step':'place','param':'hfn_opt_effort','val':'high'}]
        # Optional routed-checkpoint retry: retain all placement parameters
        # and let TD use its default routing effort instead of routability.
        route_effort = environment.get('SAIXIAN_ROUTE_EFFORT')
        if route_effort:
            assert route_effort == 'default', 'Supported route effort override: default'
            strategy['params'] = [p for p in strategy['params'] if not (p['step']=='route' and p['param']=='effort')]
        route_swap = environment.get('SAIXIAN_ROUTE_SWAP_PIN')
        if route_swap:
            assert route_swap in ('on','off'), 'Supported route pin-swap overrides: on/off'
            strategy['params'] += [{'step':'route','param':'swap_pin','val':route_swap}]
        if mapped_from and checkpoint_stage in ('place','pr'):
            assert record['place_seed_override'] == origin['place_seed_override'], 'Keep the accepted placement seed'
            original_place = [p for p in origin['physical_strategy']['parameters'] if p['step'] == 'place']
            assert [p for p in strategy['params'] if p['step'] == 'place'] == original_place, 'Placed retry may change routing parameters only'
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
        record['physical_strategy'] = {'name': requested_physical_strategy, 'base': strategy_base, 'catalog': str(catalog),
                                       'catalog_sha256': digest(catalog), 'parameters': strategy['params']}
        record['local_physical_recipe_sha256'] = digest(flow)
        if physical_strategy == 'TimingMediumEmbeddedReset':
            # import_db restores options from the checkpoint. A partial
            # strategy must start from defaults, then apply this build's
            # explicit recipe. Keep the installed TD flow untouched.
            original_flow = td_root/'doc/scripts/DefaultFlow.tcl'
            derived = original_flow.read_text(encoding='utf-8')
            assert derived.count('  set wildParams ""') == 1
            derived = derived.replace('  set wildParams ""', '  clear_param\n  set wildParams ""', 1)
            local_flow = td/'physical_flow.tcl'
            local_flow.write_text(derived, encoding='utf-8', newline='\n')
            record['local_flow'] = {'path': str(local_flow), 'sha256': digest(local_flow),
                                    'base': str(original_flow), 'base_sha256': digest(original_flow),
                                    'change': 'Clear checkpoint parameter inheritance before applying the explicit recipe.'}
            recipe = flow.read_text(encoding='utf-8')
            marker = 'source [file join $tdRoot doc scripts DefaultFlow.tcl]'
            assert recipe.count(marker) == 1
            flow.write_text(recipe.replace(marker, 'source ./physical_flow.tcl'), encoding='utf-8', newline='\n')
            record['local_physical_recipe_sha256'] = digest(flow)
        if guard_route:
            # Official set_path_margin is an optimization target, not a
            # relaxed clock. A probe confirms +0.20 ns tightens setup by
            # exactly 0.20 ns. Remove ONLY our named group before final STA.
            original_flow = td_root/'doc/scripts/DefaultFlow.tcl'
            derived = original_flow.read_text(encoding='utf-8')
            route_margin = environment.get('SAIXIAN_ROUTE_SETUP_MARGIN', '0.20')
            assert route_margin in ('0.20','0.50','1.00'), 'Supported positive routing setup targets'
            margin_command = '  set_path_margin -group codex_setup_guard -setup -global '+route_margin+'\n'
            route_start = derived.index('proc opt_route_fun {}')
            route_end = derived.index('proc bitgen_fun {}', route_start)
            route_body = derived[route_start:route_end]
            marker = '### Editable zone for opt_route ###\n'
            assert route_body.count(marker) == 1
            route_body = route_body.replace(marker, marker+margin_command, 1)
            if checkpoint_stage=='pr':
                assert route_body.count('\n  route\n')==1
                route_body=route_body.replace('\n  route\n','\n  route -incremental\n',1)
                move_location=environment.get('SAIXIAN_HDMI_REGISTER_LOCATION')
                if move_location:
                    assert re.fullmatch(r'x0[0-5][0-9]y0[0-7][0-9]',move_location)
                    cell='match_video/render/numbers/tens_reg[1]_syn_36'
                    marker='\n  route -incremental\n'
                    route_body=route_body.replace(marker,'\n  move_cells -inst {'+cell+'} -location {'+move_location+'} -mode enforce -step route\n'+marker,1)
                    record['physical_cell_relocation']={'cell':cell,'location':move_location,'mode':'enforce','stage':'route'}
                mode=environment.get('SAIXIAN_INCREMENTAL_PHYS_OPT')
                if mode:
                    assert mode in ('relocation','reroute')
                    marker='\n  route -incremental\n'
                    route_body=route_body.replace(marker,marker+'  phys_opt -post_route -effort ultra -mode '+mode+'\n  route -incremental\n',1)
                    record['post_route_physical_optimization']={'effort':'ultra','mode':mode,'incremental_route_after':True}
                if environment.get('SAIXIAN_ROUTE_ENDPOINT_RETRY')=='1':
                    summary=Path(origin['timing']['path']).read_text(errors='replace')
                    sinks=[]
                    for match in re.finditer(r'Slack\s*:\s*(-?[0-9.]+)ns\nBegin Point[^\n]*\nEnd Point\s*:\s*(\S+)',summary):
                        if float(match[1])<0 and match[2] not in sinks:sinks.append(match[2])
                    assert sinks and all(re.fullmatch(r'[A-Za-z0-9_/.$\[\]-]+',sink) for sink in sinks)
                    marker='\n  route -incremental\n'
                    route_body=route_body.replace(marker,marker+''.join('  multi_try_route -sink {'+sink+'}\n' for sink in sinks)+'  route -incremental\n',1)
                    record['endpoint_route_retries']=sinks
            marker = '  report_area -io_info -file ${prj_name}_phy.area\n'
            assert route_body.count(marker) == 1
            route_body = route_body.replace(marker, '  reset_path_margin -group codex_setup_guard\n  report_path_margin\n'+marker, 1)
            derived = derived[:route_start]+route_body+derived[route_end:]
            if guard_place:
                marker = '### Editable zone for opt_place ###\n'
                assert derived.count(marker) == 1
                derived = derived.replace(marker, marker+'  set_path_margin -group codex_setup_guard -setup -global 0.20\n', 1)
                if environment.get('SAIXIAN_HDMI_NEAR_BOUND')=='1':
                    bound='  create_bound codex_hdmi_output_near -mode soft -origin {25 1} -width 15 -height 20\n  set hdmi_output_cells [get_cells -hier -regexp {u_hdmi_phy/u2_lane_lvds_8_1/S_oddr_data_reg\\[1\\]}]\n  add_cells_to_bound -bound codex_hdmi_output_near -cells $hdmi_output_cells\n'
                    derived=derived.replace(marker,marker+bound,1)
                    record['physical_soft_bound']={'name':'codex_hdmi_output_near','origin':[25,1],'width':15,'height':20,'rtl_register':'u_hdmi_phy/u2_lane_lvds_8_1/S_oddr_data_reg[1]'}
            local_flow = td/'physical_flow.tcl'
            local_flow.write_text(derived, encoding='utf-8', newline='\n')
            record['local_flow'] = {'path': str(local_flow), 'sha256': digest(local_flow),
                                    'base': str(original_flow), 'base_sha256': digest(original_flow),
                                    'change': 'Use +0.20ns placement and +'+route_margin+'ns routing setup optimization targets; reset the named group before final routed timing.'}
            record['optimization_guard'] = {'setup_margin_ns': 0.20,'route_setup_margin_ns':float(route_margin),
                'during': ['place','route'] if guard_place else ['route'],
                'restored_before_final_timing': True,'incremental_routing':checkpoint_stage=='pr'}
            recipe = flow.read_text(encoding='utf-8')
            marker = 'source [file join $tdRoot doc scripts DefaultFlow.tcl]'
            assert recipe.count(marker) == 1
            flow.write_text(recipe.replace(marker, 'source ./physical_flow.tcl'), encoding='utf-8', newline='\n')
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
        synthesis_base = {'AreaOptimizeSparseCE': 'AreaOptimizeHigh', 'AreaOptimizeGlobalHFN': 'AreaOptimizeHigh','AreaPackHigh':'AreaOptimizeHigh'}.get(synthesis_strategy, synthesis_strategy)
        strategy = dict(json.loads(catalog.read_text(encoding='utf-8'))[synthesis_base])
        strategy['params'] = list(strategy['params'])
        if synthesis_strategy == 'AreaPackHigh':
            strategy['params'].append({'step':'gate','param':'pack_effort','val':'high'})
        if synthesis_strategy == 'AreaOptimizeSparseCE':
            strategy['params'].append({'step': 'rtl', 'param': 'min_ce_fanout', 'val': '64'})
        if synthesis_strategy == 'AreaOptimizeGlobalHFN':
            strategy['params'].append({'step': 'flow', 'param': 'hfn_to_clock', 'val': '1000'})
        assert strategy['is_syn'] == 'syn'
        assert all(p['step'] in ('rtl', 'gate') or (p['step'],p['param']) == ('flow','hfn_to_clock') for p in strategy['params'])
        flow = td/'build_board.tcl'
        recipe = flow.read_text(encoding='utf-8')
        position = recipe.index('set tdRoot ')
        parameters = ''.join('lappend phyWildParams {'+p['step']+'} {'+p['param']+'} {'+p['val']+'}\n' for p in strategy['params'])
        flow.write_text(recipe[:position]+parameters+recipe[position:], encoding='utf-8', newline='\n')
        record['synthesis_strategy'] = {'name': synthesis_strategy, 'base': synthesis_base, 'catalog': str(catalog),
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
    if record.get('local_flow'):
        record['local_flow_unchanged'] = digest(Path(record['local_flow']['path'])) == record['local_flow']['sha256']
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
              and record.get('local_flow_unchanged', True)
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
    parser.add_argument('--checkpoint-stage', choices=('gate','place'), default='gate', help='Reuse mapping or placement; placement reuse retains its placement parameters')
    args = parser.parse_args()
    if args.action == 'stage':
        stage(args.work.resolve(), args.b_work.resolve() if args.b_work else None)
    else:
        build(args.action, args.work.resolve(), args.mapped_from.resolve() if args.mapped_from else None, args.checkpoint_stage)
