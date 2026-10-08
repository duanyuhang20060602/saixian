"""Prototype an FPGA photo filter using the existing line RAM and pipeline.

Generates isolated RTL and test benches; never changes production HDL or bits.
The photo output is an RTL simulation, not an AI restoration or board capture.
"""
from pathlib import Path
import argparse
import subprocess
import numpy as np
from PIL import Image, ImageDraw
from compare_scaling import rgb565


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[2]
    source = (root/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8-sig')
    start = source.index('module saixian_adaptive_enhance #(')
    end = source.index('\nendmodule', start) + len('\nendmodule')
    module = source[start:end]
    if 'PHOTO_SMOOTH' not in module:
        raise RuntimeError('Photo filter parameter missing')
    (work/'photo_filter.v').write_text(module, encoding='utf-8')
    bench = (root/'doc/tools/tb_image_stage.v').read_text(encoding='utf-8-sig')
    (work/'tb_image_stage.v').write_text(bench, encoding='utf-8')
    reference = (root/'tests/tb_photo_detail.v').read_text(encoding='utf-8-sig')
    (work/'tb_photo_reference.v').write_text(reference, encoding='utf-8')
    log = []
    def run(cmd):
        result = subprocess.run(cmd, capture_output=True, text=True)
        log.append(result.stdout + result.stderr)
        if result.returncode:
            (work/'simulation.log').write_text('\n'.join(log), encoding='utf-8')
            raise RuntimeError('RTL command failed: ' + str(cmd))

    iverilog = 'C:/iverilog/bin/iverilog.exe'
    vvp = 'C:/iverilog/bin/vvp.exe'
    run([iverilog, '-g2012', '-s', 'tb_photo_detail', '-o', str(work/'reference.vvp'),
         str(work/'tb_photo_reference.v'), str(work/'photo_filter.v')])
    run([vvp, str(work/'reference.vvp')])
    run([iverilog, '-g2012', '-s', 'tb_image_stage', '-P', 'tb_image_stage.PHOTO_SMOOTH=1', '-o', str(work/'photo.vvp'),
         str(work/'tb_image_stage.v'), str(work/'photo_filter.v')])
    run([iverilog, '-g2012', '-s', 'tb_image_stage', '-o', str(work/'baseline.vvp'),
         str(work/'tb_image_stage.v'), str(root/'src/user_source/hdl_source/top_tf_hdmi_audio.v')])
    original = Image.open(root/'doc/TF卡上卡素材_20260925/01.bmp').convert('RGB')
    pixels = rgb565(np.asarray(original))
    packed = (pixels[...,0] << 16) | (pixels[...,1] << 8) | pixels[...,2]
    (work/'input.hex').write_text(''.join(f'{int(p):06x}\n' for p in packed.flat), encoding='ascii')
    outputs = []
    for kind in ['baseline', 'photo']:
        run([vvp, str(work/(kind+'.vvp')), '+IN='+str(work/'input.hex'), '+OUT='+str(work/(kind+'.csv'))])
        words = np.loadtxt(work/(kind+'.csv'), delimiter=',', converters=lambda s: int(s,16), dtype=np.uint32)
        a = np.stack([(words[:,1]>>16)&255, (words[:,1]>>8)&255, words[:,1]&255], axis=-1)
        im = Image.fromarray(a.astype(np.uint8).reshape(720,1280,3))
        im.save(work/(kind+'.png'))
        outputs.append(im)
    sheet = Image.new('RGB',(1200,610),'#202020')
    draw = ImageDraw.Draw(sheet)
    for i,(im,label) in enumerate(zip([original]+outputs, ['Original source', 'Current RTL / gain 1', 'Photo smoothing prototype / gain 1'])):
        draw.text((i*400+8,10),label,fill='white')
        sheet.paste(im.resize((384,216),Image.Resampling.NEAREST),(i*400+8,35))
        sheet.paste(im.crop((710,260,900,420)).resize((380,320),Image.Resampling.NEAREST),(i*400+8,280))
    sheet.save(work/'comparison.png')
    (work/'simulation.log').write_text('\n'.join(log), encoding='utf-8')
    print('\n'.join(log))
    print('Prototype RTL and comparison:',work)
    print('RTL simulation only. No resource/timing or board claim.')


if __name__ == '__main__':
    main()
