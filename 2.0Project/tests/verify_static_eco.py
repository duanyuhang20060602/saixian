"""Audit the frozen native checkpoint, exact RTL delta and implemented ECO."""
from pathlib import Path
import argparse, hashlib, json, re, zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'src/td_project/static_bus_baseline'
WORK = ROOT / 'validation/key2_tf_20261010'
TARGET = r'\u_tf_animation/loader/header_reg[234]_syn_4'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

def expected_source(name, data):
    text = data.decode('utf-8').replace('\r\n', '\n')
    if name.endswith('/delta_memory.v'):
        text = text.replace('output [159:0] debug_data,output [3:0] wr_dm,output patch_drained',
                            'output [159:0] debug_data,output [3:0] wr_dm,output patch_drained,output local_clear')
        text = text.replace('assign idle=state==IDLE;', 'assign idle=state==IDLE;\n'
                            '// FIFO-only housekeeping never owns the shared physical SDRAM bus.\n'
                            'assign local_clear=state==VIDEO_CLEAR || state==COMMAND_CLEAR;')
    elif name.endswith('/saixian_tf_preload.v'):
        text = text.replace('wire bus_idle,cache_ready,upload_done;',
                            'wire bus_idle,cache_ready,upload_done,local_clear;')
        text = text.replace('assign mode_mem=session_mem[2] && !bus_idle;',
                            '// Local FIFO clears may overlap outstanding photo reads and responses.\n'
                            'assign mode_mem=session_mem[2] && !bus_idle && !local_clear;')
        text = text.replace('bus_idle,crc_sync,,wr_dm,patch_drained);',
                            'bus_idle,crc_sync,,wr_dm,patch_drained,local_clear);')
    return text

def check_sources():
    manifest = json.loads((BASE/'baseline.json').read_text(encoding='utf-8'))
    for name, digest in manifest['files'].items():
        assert sha(BASE/name) == digest, f'Frozen baseline changed: {name}'
    with zipfile.ZipFile(BASE/'baseline_source.zip') as z:
        prefix = '2.0Project/'
        release = prefix+'releases/key2_tf_preload_20261010/'
        report = json.loads(z.read(release+'validation.json'))
        bit = z.read(release+'SAIXIAN_KEY2_TF_20261010.bit')
        assert hashlib.sha256(bit).hexdigest() == manifest['baseline_bit_sha256'] == report['bit_sha256']
        project_name = 'src/td_project/SAIXIAN_KEY2_TF_20261010.al'
        original_project = z.read(prefix+project_name)
        assert hashlib.sha256(original_project).hexdigest() == report['source_sha256'][project_name]
        def project_config(text):
            text = text.replace('\r\n', '\n').replace('P&R', 'P&amp;R')
            return re.sub(r'(<Project[^>]* Path=")[^"]*', r'\1PROJECT_PATH', text)
        assert project_config((ROOT/project_name).read_text(encoding='utf-8')) == project_config(original_project.decode('utf-8'))
        count = 0
        for name, digest in report['source_sha256'].items():
            if not name.startswith('src/user_source/'):
                continue
            original = z.read(prefix+name)
            assert hashlib.sha256(original).hexdigest() == digest
            assert (ROOT/name).read_text(encoding='utf-8') == expected_source(name, original), name
            count += 1
        assert count > 50
    return count

def normalize(text):
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'open_n\d+', 'UNCONNECTED', text)
    return re.sub(r'\s+', ' ', text).strip()

def check_netlists():
    folder = WORK/'static_bus_eco'
    before = (folder/'baseline_phy.v').read_text(encoding='utf-8')
    target = before.index(TARGET)
    start = before.rfind('EG_PHY_MSLICE #(', 0, target)
    end = before.index(');', target)+2
    block = before[start:end]
    old = ".INIT_LUT0(16'b0000111100000000)"
    assert block.count(old) == 1
    block = block.replace(old, ".INIT_LUT0(16'b0000000100000000)")
    marker = TARGET+'  ('
    assert block.count(marker) == 1
    block = block.replace(marker, marker+'\n'
        '    .a({open_n0,\\u_tf_animation/memory_bus/state_reg_syn_1 [5]}),\n'
        '    .b({open_n0,\\u_tf_animation/memory_bus/state_reg_syn_1 [6]}),')
    expected = normalize(before[:start]+block+before[end:])
    for name in ('patched_phy.v', 'routed_phy.v'):
        assert normalize((folder/name).read_text(encoding='utf-8')) == expected, name
    # Native LUT index order is {D,C,B,A}. A/B are command/video clear,
    # C is IDLE and D is the existing synchronized cache-session enable.
    for index in range(16):
        command, video, idle, session = ((index>>bit)&1 for bit in range(4))
        actual = (0x0100>>index)&1
        assert actual == (session and not idle and not (command or video))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--sources-only', action='store_true')
    options = parser.parse_args()
    count = check_sources()
    if options.sources_only:
        print(f'PASS frozen checkpoint and {count} source files: only the two exact bus-control edits')
    else:
        check_netlists()
        message = (f'PASS static ECO: frozen checkpoint and {count} source files audited; '
                   'complete implemented netlist changes only one LUT and two unused input pins; '
                   'all 16 LUT rows match RTL bus ownership; post-route logical netlist unchanged')
        (WORK/'tb_static_eco_truth.log').write_text(message+'\n', encoding='utf-8')
        print(message)
