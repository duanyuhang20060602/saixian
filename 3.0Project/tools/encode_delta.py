"""Lossless delta coding relative to the original GIF's RGB565 raster."""
from pathlib import Path
from PIL import Image
import hashlib, json, struct, zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'examples/TF卡素材/source.gif'


def encode(words, previous=None):
    stream = []; pos = 0
    while pos < len(words):
        if previous is not None and words[pos] == previous[pos]:
            end = pos + 1
            while end < len(words) and words[end] == previous[end]: end += 1
            stream.append(end - pos); pos = end
            continue
        run = 1
        while pos + run < len(words) and words[pos + run] == words[pos] and (
                previous is None or words[pos + run] != previous[pos + run]): run += 1
        if run >= 3:
            stream += [0x80000000 | run, words[pos]]; pos += run
            continue
        start = pos; pos += run
        while pos < len(words):
            if previous is not None and words[pos] == previous[pos]: break
            if pos + 2 < len(words) and words[pos] == words[pos + 1] == words[pos + 2]: break
            pos += 1
        stream += [0x40000000 | (pos - start), *words[start:pos]]
    return struct.pack('<' + 'I' * len(stream), *stream)


def decode(blob, base):
    result = list(base); cursor = 0; pointer = 0
    while pointer < len(blob):
        cmd, = struct.unpack_from('<I', blob, pointer); pointer += 4
        kind, count = cmd >> 30, cmd & 0x3fffffff
        assert kind < 3 and 0 < count <= len(result) - cursor
        if kind == 1:
            result[cursor:cursor + count] = struct.unpack_from('<' + 'I' * count, blob, pointer)
            pointer += count * 4
        elif kind == 2:
            word, = struct.unpack_from('<I', blob, pointer); pointer += 4
            result[cursor:cursor + count] = [word] * count
        cursor += count
    assert cursor == len(result) and pointer == len(blob)
    return result


def prepare():
    (ROOT / 'examples/TF卡素材').mkdir(exist_ok=True); (ROOT / 'releases').mkdir(exist_ok=True)
    gif = Image.open(SOURCE); frames = []; delays = []
    for i in range(gif.n_frames):
        gif.seek(i)
        # GIF disposal/compositing is handled by Pillow; no redesigned geometry.
        rgba = gif.convert('RGBA')
        assert rgba.size == (480, 480)
        black = Image.new('RGBA', rgba.size, (0, 0, 0, 255)); black.alpha_composite(rgba)
        rgb = black.convert('RGB')
        pixels = [((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
                  for r, g, b in rgb.get_flattened_data()]
        frames.append([pixels[j] | (pixels[j+1] << 16) for j in range(0, len(pixels), 2)])
        delays.append(gif.info.get('duration', 40))
    # Bootstrap key frame is separate from the last->first loop delta.
    expected = [frames[0], *frames[1:], frames[0]]
    previous = [None, *frames[:-1], frames[-1]]
    durations = [delays[0], *delays[1:], delays[0]]
    streams = [encode(f, p) for f, p in zip(expected, previous)]
    for blob, f, p in zip(streams, expected, previous):
        assert decode(blob, p or [0] * len(f)) == f
    table = bytearray(((len(streams) * 32 + 511) // 512) * 512)
    payload = bytearray(); base_sector = 1 + len(table) // 512
    for i, (blob, f, delay) in enumerate(zip(streams, expected, durations)):
        raw = struct.pack('<' + 'I' * len(f), *f)
        struct.pack_into('<8I', table, i * 32, (base_sector + len(payload)//512)*128,
                         len(blob)//4, delay*50000, zlib.crc32(raw), zlib.crc32(blob),
                         0 if i == len(streams)-1 else i, 0, 0)
        payload += blob; payload += bytes((-len(blob)) % 512)
    header = bytearray(512); total_bytes = 512 + len(table) + len(payload)
    struct.pack_into('<8s4H7I', header, 0, b'SXDLT001', 1, 512, 480, 480,
                     len(frames), total_bytes, 115200, 1, 32,
                     zlib.crc32(table+payload), len(streams))
    blob = bytes(header + table + payload)
    assert len(blob)//4 + 230400 <= 2097152
    target = ROOT / 'examples/TF卡素材/TROPHY.DLT'; target.write_bytes(blob)
    (ROOT / 'examples/TF卡素材/package.hex').write_text('\n'.join(f'{b:02x}' for b in blob)+'\n')
    work = Path('E:/Codex/Temp/saixian_delta_tests'); work.mkdir(parents=True,exist_ok=True)
    for i, f in enumerate(expected):
        (work / f'frame{i}.hex').write_text('\n'.join(f'{v:08x}' for v in f)+'\n')
    previews=[]
    for f in frames:
        pixels=[]
        for word in f:
            for shift in (0,16):
                v=(word>>shift)&65535;r=(v>>11)&31;g=(v>>5)&63;b=v&31
                pixels.append(((r<<3)|(r>>2),(g<<2)|(g>>4),(b<<3)|(b>>2)))
        im=Image.new('RGB',(480,480)); im.putdata(pixels);previews.append(im)
    previews[0].save(ROOT / 'releases/原动作预览.gif',save_all=True,append_images=previews[1:],
                     duration=delays,loop=0,disposal=2)
    previews[0].save(ROOT / 'releases/首帧.png')
    canvases=[]
    for im in previews:
        canvas=Image.new('RGB',(1280,720),(0,0,0));canvas.paste(im,(400,120));canvases.append(canvas)
    canvases[0].save(ROOT/'releases/单板画面预览.gif',save_all=True,append_images=canvases[1:],
                     duration=delays,loop=0,disposal=2)
    report=dict(source_sha256=hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                frame_count=len(frames),descriptors=len(streams),durations_ms=delays,
                package_bytes=len(blob),payload_encoded_bytes=sum(map(len,streams)),
                package_sha256=hashlib.sha256(blob).hexdigest(),
                exact_rgb565_reconstruction=True,geometry_changed=False,
                decoded_buffers_bytes=115200*4*2,
                sdram_required_bytes=len(blob)+115200*4*2,
                encoded_frame_bytes=list(map(len,streams)))
    (ROOT / 'examples/TF卡素材/manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))
    return blob


if __name__=='__main__':prepare()
