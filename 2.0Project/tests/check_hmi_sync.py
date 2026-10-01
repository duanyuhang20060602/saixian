"""Read saved HMI active records and check the screen/FPGA sync contract.

This checks the native editor's saved source, not dead records or a text export.
It does not replace the editor compiler or a physical screen test.
"""
import argparse
import hashlib
import json
import re
import struct
from pathlib import Path


def read_records(path):
    data = path.read_bytes()
    records = {}
    count = struct.unpack_from('<I', data)[0]
    assert 4 + count * 28 <= len(data), 'Invalid record table'
    for i in range(count):
        base = 4 + i * 28
        name = data[base:base+16].split(b'\0')[0].decode('gb18030')
        offset, length = struct.unpack_from('<II', data, base+16)
        if data[base+24] != 0:
            continue
        assert offset + length <= len(data), name
        if not (name.endswith('.pa') or name == 'Program.s'):
            continue
        payload = data[offset:offset+length]
        strings = [m.group().decode('ascii') for m in re.finditer(rb'[\x20-\x7e]{4,}', payload)]
        components = {}
        component_starts = []
        owner = None
        for m in re.finditer(rb'(objname|vscope|txt_maxl|en|maxval|minval|sta|picc)\x00', payload):
            start = m.start()
            size = struct.unpack_from('<I', payload, start-4)[0]
            if not 16 <= size <= 256:
                continue
            value = payload[start+16:start+size]
            key = m.group().rstrip(b'\0').decode('ascii')
            if key == 'objname':
                owner = value.rstrip(b'\0').decode('gb18030')
                components[owner] = {}
                component_starts.append((start, owner))
            elif owner is not None:
                components[owner][key] = int.from_bytes(value, 'little')
        for index, (start, component_name) in enumerate(component_starts):
            end = component_starts[index+1][0] if index+1 < len(component_starts) else len(payload)
            components[component_name]['event_strings'] = [m.group().decode('ascii') for m in re.finditer(rb'[\x20-\x7e]{4,}', payload[start:end]) if re.match(rb'(printh |prints |page |vis |.*\.en=|.*\.val=)', m.group())]
        records[name] = {'strings': strings, 'components': components}
    return data, records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1]/'hmi/saixian_UART_HMI.HMI')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    data, records = read_records(args.source)
    for page, record in records.items():
        for name, props in record['components'].items():
            if props.get('sta') == 0 and 'picc' in props:
                assert props['picc'] != 65535, f'{page}/{name}: cropped background image is unset (screen error 04)'
    for index in range(5):
        assert f'printh 55 30 0{index} 00 ff ff ff' in records[f'{index}.pa']['strings'], f'Page {index} notification missing'
    expected = {
        '0.pa': ['t_p', 't_m', 't_e'],
        '1.pa': ['h_sharp', 'n_sharp', 'h_bright', 'n_bright', 'h_contrast', 'n_contrast', 'h_saturation', 'n_saturation', 'h_volume', 'n_volume', 'bt_invert', 'bt_vintage'],
        '2.pa': ['t4', 't3', 'n_state'],
    }
    for page, names in expected.items():
        for name in names:
            assert records[page]['components'][name]['vscope'] == 1, f'{page}/{name} must be global'
    for name in ['t4', 't3']:
        assert records['2.pa']['components'][name]['txt_maxl'] >= 5, name
    settings = records['1.pa']
    assert settings['components']['h_sharp']['maxval'] == 3
    for name in ['h_bright', 'h_contrast', 'h_saturation', 'h_volume']:
        assert settings['components'][name]['maxval'] == 100, name
    assert not any(s in ['bt_invert.val=0', 'bt_vintage.val=0'] for s in settings['strings']), 'Settings reset on entry'
    game = records['2.pa']
    assert game['components']['tm0']['en'] == 0
    for command in ['06', '07', '03']:
        assert f'printh 55 {command} 00 00 ff ff ff' in game['strings'], command
    for button, command in [('b_pulse', '06'), ('b_continue', '07'), ('b_end', '03')]:
        assert f'printh 55 {command} 00 00 ff ff ff' in game['components'][button]['event_strings'], button
    assert not any('tm0.en=1' in s or 'n_total.val=' in s or 'j0.val=' in s or 'printh 55 02' in s for s in game['strings']), 'Old screen timing or toggle command remains'
    for name in ['j0', 'n_min', 'n_sec', 'n_total', 'n_state']:
        assert f'vis {name},0' in game['strings'], name
    assert 'bkcmd=0' in records['Program.s']['strings']
    assert 'baud=115200' in records['Program.s']['strings']
    for command in ['01', '04', '05', '08']:
        assert f'printh 55 {command} 00 00 ff ff ff' in records['0.pa']['strings'], command
    for command in ['20', '21', '22', '23']:
        assert f'printh 55 {command} 00 00 ff ff ff' in records['3.pa']['strings'], command
    result = {'source': str(args.source.resolve()), 'sha256': hashlib.sha256(data).hexdigest(), 'check': 'PASS', 'records': records}
    if args.report:
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('PASS saved HMI: page notifications, 18 global feedback controls, timer disabled, explicit pause/resume, settings and retained music/result commands')


if __name__ == '__main__':
    main()
