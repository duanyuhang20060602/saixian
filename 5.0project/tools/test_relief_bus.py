"""Independent SXDLT oracle and full-frame relief/memory regressions."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, re, shutil, struct, subprocess, time, zlib
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
GEOMETRY = ['common/fluid/' + n for n in ['water_drop_small.v', 'water_reader.v', 'water_effect_map_base.v', 'water_priority_map.v', 'water_surface.v', 'water_blend.v', 'water_cache.v', 'water_reconstruct.v']]
FRAMEBUFFER = ['src/board_a/user_source/hdl_source/' + n for n in ['SD/frame_read_write.v', 'SD/frame_fifo_write.v', 'IP/afifo_32_16_256.v', 'IP/afifo_16_32_256.v']]
PLAYER = ['common/photo_relief_player.v', 'common/photo_relief_motion.v']
READER = ['common/photo_sd/photo_dlt_reader.v', 'common/photo_sd/photo_dlt_header.v', 'common/photo_color_format.v']
JOBS = {'player': ['tests/tb_relief_player.v', *PLAYER], 'bus': ['tests/tb_relief_bus.v', *PLAYER, 'common/photo_award_memory.v', *GEOMETRY, *FRAMEBUFFER],
        'reader': ['tests/tb_relief_reader.v', *READER], 'legacy_reader': ['tests/tb_relief_reader.v', *READER]}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def savehex(path, values, width=8):
    np.savetxt(path, np.asarray(values), fmt='%0' + str(width) + 'x')

def decode(path):
    """Decode file commands, independently of both packer and RTL state machine."""
    blob = path.read_bytes()
    assert blob[:8] in (b'SXDLT005', b'SXDLT008')
    version, header_bytes, width, height = struct.unpack_from('<4H', blob, 8)
    assert version == int(chr(blob[7])) and (header_bytes, width, height) == (512, 1280, 720)
    assert struct.unpack_from('<I', blob, 20)[0] == len(blob)
    assert struct.unpack_from('<I', blob, 36)[0] == zlib.crc32(blob[512:])
    offset, length, duration, frame_crc, stream_crc, sequence, r0, r1 = struct.unpack_from('<8I', blob, 512)
    assert duration > 0 and sequence == r0 == r1 == 0
    stream = blob[offset * 4:(offset + length) * 4]
    assert len(stream) == length * 4 and zlib.crc32(stream) == stream_crc
    encoded = np.frombuffer(stream, dtype='<u4')
    decoded = []; i = 0
    while i < len(encoded):
        command = int(encoded[i]); i += 1
        kind, count = command >> 30, command & 0x3fffffff
        assert kind in (1, 2) and 0 < count <= 460800 - len(decoded)
        if kind == 1:
            assert i + count <= len(encoded)
            decoded.extend(encoded[i:i + count]); i += count
        else:
            assert i < len(encoded)
            decoded.extend([encoded[i]] * count); i += 1
    plate = np.asarray(decoded, dtype='<u4')
    assert len(plate) == 460800 and zlib.crc32(plate.tobytes()) == frame_crc
    frames, tail_offset, tail_words, magic, period = struct.unpack_from('<5I', blob, 256)
    assert (frames, magic) == ((24, 0x524c4638) if version == 8 else (120, 0x53505835))
    assert tail_words == (524288 if version==8 else 230400) and period == 6
    tail = np.frombuffer(blob, dtype='<u4', count=tail_words, offset=tail_offset * 4)
    expected = np.concatenate(((plate << 16) | (plate >> 16), tail))
    return blob, plate, tail, expected

def decode_hq(tail):
    """Independent native PackBits decoder; no packer helpers are imported."""
    raw=tail.astype('<u4').tobytes()
    assert struct.unpack_from('<8I',raw)==(0x38514852,576,576,24,256,64,6208,80128)
    palettes=np.frombuffer(raw,dtype='<u4',count=6144,offset=256).reshape(24,256)
    assert np.all(palettes[:,0]==0)
    descriptors=np.frombuffer(raw,dtype='<u4',count=13824,offset=6208*4).reshape(24,576)
    images=np.zeros((24,576,576),dtype=np.uint8);end=80128
    for f in range(24):
        for y in range(576):
            value=int(descriptors[f,y]);offset=value&0x1fffff;count=value>>21
            assert offset>=end and not any(raw[end:offset]) and 0<=count<=768 and offset+count<=len(raw)
            x=0;i=offset;end=offset+count
            while i<end:
                command=raw[i];i+=1;n=(command&127)+1;assert x+n<=576
                if command<128:
                    assert i+n<=end;images[f,y,x:x+n]=np.frombuffer(raw,dtype=np.uint8,count=n,offset=i);i+=n
                else:
                    assert i<end;images[f,y,x:x+n]=raw[i];i+=1
                x+=n
    assert not any(raw[end:])
    return palettes,images

def vectors(directory, source, relief=False):
    directory.mkdir(parents=True, exist_ok=True)
    blob, plate, tail, expected = decode(source)
    savehex(directory / 'award_file.hex', np.frombuffer(blob, dtype='<u4'))
    savehex(directory / 'award_expected.hex', expected)
    if relief:
        savehex(directory / 'relief_tail.hex', tail)
        base = plate.view('<u2').reshape(720, 1280).astype(np.int32)
        savehex(directory / 'relief_base.hex', base.ravel(), 4)
        palettes,indices=decode_hq(tail)
        def expand(p):
            r, g, b = (p >> 11) & 31, (p >> 5) & 63, p & 31
            return np.stack(((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)), axis=-1)
        images = []
        for angle in range(2):
            palette=palettes[angle]
            token = np.zeros((720,1280),dtype=np.uint8)
            sample=np.arange(576)
            token[48:624,352:928]=indices[angle][sample[:,None],sample[None,:]]
            cup=token!=0
            surface=np.where(cup,palette[token]&65535,base).astype(np.int32)
            color=expand(np.where(cup,palette[token]>>16,base).astype(np.int32))
            nx, ny, nz = (surface >> 11) & 31, (surface >> 6) & 31, (surface >> 1) & 31
            nx, ny = np.where(nx >= 16, nx - 32, nx) * 2, np.where(ny >= 16, ny - 32, ny) * 2
            dot = nx * -16 + ny * 6 + nz * 16
            diffuse, specular = np.clip(dot // 4, 0, 255), np.clip(dot + nz * 16 - 1024, 0, 255)
            wall = (~cup) & ((base & 1) != 0)
            shaded = color.copy()
            shaded[wall] = np.stack((24 + diffuse // 2, 12 + diffuse // 4, 3 + diffuse // 16), axis=-1)[wall]
            metal = color // 2 + (color * (diffuse[...,None]//16)) // 32 + np.stack((specular // 2, specular // 4, specular // 8), axis=-1)
            shaded[cup] = np.clip(metal, 0, 255)[cup]
            shaded=np.rint(510*shaded/(255+shaded)).astype(np.int32)
            images.append(((shaded[..., 0] << 16) | (shaded[..., 1] << 8) | shaded[..., 2]).ravel())
        savehex(directory / 'relief_golden.hex', np.concatenate(images), 6)
        for p in (ROOT / 'common/fluid').glob('*.hex'):
            shutil.copy2(p, directory / p.name)
    return len(blob) // 4

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--asset', type=Path, default=ROOT / 'award_media/RELIEF720.DLT')
    ap.add_argument('--legacy', type=Path, default=ROOT / 'award_media/AWARD720.DLT')
    ap.add_argument('--out', type=Path, default=Path('E:/Codex/Work/saixian-relief-tests'))
    ap.add_argument('--only', nargs='+', choices=JOBS)
    ap.add_argument('--jobs', type=int, default=3)
    a = ap.parse_args(); selected = a.only or list(JOBS)
    out = a.out.resolve(); out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy(); temp = out / 'temp'; temp.mkdir(exist_ok=True)
    env.update(TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp))
    asset_hash = digest(a.asset); legacy_hash = digest(a.legacy)
    word_counts = {}
    if any(n != 'legacy_reader' for n in selected):
        word_counts['relief'] = vectors(out / 'relief', a.asset, relief=True)
    if 'legacy_reader' in selected:
        word_counts['legacy'] = vectors(out / 'legacy', a.legacy)
    def run(name):
        started = time.monotonic()
        directory = out / ('legacy' if name == 'legacy_reader' else 'relief')
        files = [ROOT / p for p in JOBS[name]]
        hashes = {p.relative_to(ROOT).as_posix(): digest(p) for p in files + [Path(__file__)]}
        extra = ['-DWATER_SIM', '-DVICTORY_SIM', '-DRELIEF_SIM', '-DFX11_ROM_ROOT=""']
        if name in ('reader', 'legacy_reader'):
            extra += ['-P', 'tb.FILE_WORDS=' + str(word_counts['legacy' if name == 'legacy_reader' else 'relief']),'-P','tb.EXPECTED_WORDS='+str(691200 if name=='legacy_reader' else 985088)]
        binary = directory / (name + '.vvp')
        p = subprocess.run(['C:/iverilog/bin/iverilog.exe', '-g2012', *extra, '-s', 'tb', '-o', str(binary), *map(str, files)], cwd=directory, env=env, capture_output=True, text=True)
        log = p.stdout + p.stderr
        if p.returncode == 0:
            p = subprocess.run(['C:/iverilog/bin/vvp.exe', str(binary)], cwd=directory, env=env, capture_output=True, text=True, timeout=900)
            log += p.stdout + p.stderr
        log_path = out / (name + '.log'); log_path.write_text(log, encoding='utf-8')
        unchanged = all(digest(ROOT / path) == value for path, value in hashes.items()) and digest(a.asset) == asset_hash and digest(a.legacy) == legacy_hash
        passed = p.returncode == 0 and 'PASS ' in log and not re.search(r'(?im)^(ERROR:|FATAL:)', log) and unchanged
        print(name + ': ' + next((s for s in log.splitlines() if s.startswith('PASS ')), log[-2500:]), flush=True)
        return {'test': name, 'passed': passed, 'inputs_unchanged': unchanged, 'seconds': round(time.monotonic() - started, 2),
                'inputs_sha256': hashes, 'asset_sha256': asset_hash, 'legacy_asset_sha256': legacy_hash, 'log_sha256': digest(log_path)}
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        results = list(pool.map(run, selected))
    report = out / 'results.json'
    previous = json.loads(report.read_text()) if report.exists() and a.only else []
    previous = [r for r in previous if r['test'] not in selected]
    report.write_text(json.dumps(previous + results, indent=2) + '\n', encoding='utf-8')
    if not all(r['passed'] for r in results):
        raise SystemExit('Relief regression failed')

if __name__ == '__main__':
    main()
