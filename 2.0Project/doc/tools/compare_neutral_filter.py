"""Run neutral-luminance RTL experiments without changing production HDL.

Compare released spatial processing with a stronger range-gated average.
This is a simulation experiment; it does not imply an improved FPGA release.
"""
from pathlib import Path
import argparse
import subprocess
import numpy as np
from PIL import Image, ImageDraw
from compare_scaling import rgb565


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--work',type=Path,required=True)
    args=parser.parse_args()
    work=args.work.resolve();work.mkdir(parents=True,exist_ok=True)
    root=Path(__file__).resolve().parents[2]
    source=(root/'src/user_source/hdl_source/top_tf_hdmi_audio.v').read_text(encoding='utf-8-sig')
    begin=source.index('module saixian_adaptive_enhance #(')
    end=source.index('\nendmodule',begin)+len('\nendmodule')
    module=source[begin:end]
    old='''        if(detail>0) detail_term=-((detail+1)>>>1);
        else detail_term=((-detail+1)>>>1);'''
    if module.count(old)!=1:raise RuntimeError('Filter changed; review experiment')
    stronger=module.replace(old,'        detail_term=-detail;')
    (work/'released.v').write_text(module,encoding='utf-8')
    (work/'stronger.v').write_text(stronger,encoding='utf-8')
    reference=(root/'tests/tb_photo_detail.v').read_text(encoding='utf-8-sig')
    reference=reference.replace('dt=(d>0) ? -((d+1)/2) : ((-d+1)/2);','dt=-d;')
    (work/'reference.v').write_text(reference,encoding='utf-8')
    bench=root/'doc/tools/tb_image_stage.v'
    log=[]
    def run(cmd):
        p=subprocess.run(cmd,capture_output=True,text=True)
        log.append(p.stdout+p.stderr)
        (work/'simulation.log').write_text('\n'.join(log),encoding='utf-8')
        if p.returncode:raise RuntimeError('Simulation failed: '+str(cmd))
    iv='C:/iverilog/bin/iverilog.exe';vvp='C:/iverilog/bin/vvp.exe'
    run([iv,'-g2012','-s','tb_photo_detail','-o',str(work/'reference.vvp'),str(work/'reference.v'),str(work/'stronger.v')])
    run([vvp,str(work/'reference.vvp')])
    source_image=Image.open(root/'doc/TF卡上卡素材_20260925/01.bmp').convert('RGB')
    pixels=rgb565(np.asarray(source_image))
    packed=(pixels[...,0]<<16)|(pixels[...,1]<<8)|pixels[...,2]
    (work/'input.hex').write_text(''.join(f'{int(p):06x}\n' for p in packed.flat),encoding='ascii')
    images=[Image.fromarray(pixels.astype(np.uint8))]
    measures={}
    for name in ['released','stronger']:
        run([iv,'-g2012','-s','tb_image_stage','-P','tb_image_stage.PHOTO_SMOOTH=1',
             '-P','tb_image_stage.FIXED_GAIN=0','-o',str(work/(name+'.vvp')),str(bench),str(work/(name+'.v'))])
        run([vvp,str(work/(name+'.vvp')),'+IN='+str(work/'input.hex'),'+OUT='+str(work/(name+'.csv'))])
        words=np.loadtxt(work/(name+'.csv'),delimiter=',',converters=lambda s:int(s,16),dtype=np.uint32)
        out=np.stack([(words[:,1]>>16)&255,(words[:,1]>>8)&255,words[:,1]&255],axis=-1).astype(np.uint8).reshape(720,1280,3)
        im=Image.fromarray(out);im.save(work/(name+'.png'));images.append(im)
        diff=out.astype(np.int32)-pixels
        measures[name]=dict(mean_rgb_change=float(diff.mean()),mean_absolute_rgb_change=float(np.abs(diff).mean()))
    sheet=Image.new('RGB',(1200,610),'#202020');draw=ImageDraw.Draw(sheet)
    for i,(im,label) in enumerate(zip(images,['RGB565 source / no tone lift','Released smoothing / no tone lift','Stronger smoothing / no tone lift'])):
        draw.text((400*i+8,10),label,fill='white')
        sheet.paste(im.resize((384,216),Image.Resampling.NEAREST),(400*i+8,35))
        sheet.paste(im.crop((710,260,900,420)).resize((380,320),Image.Resampling.NEAREST),(400*i+8,280))
    sheet.save(work/'comparison.png')
    import json
    (work/'measures.json').write_text(json.dumps(measures,indent=2),encoding='utf-8')
    print('\n'.join(log));print(measures)
    print('Neutral-gain RTL experiment only; no new routed or board-validated bitstream.')


if __name__=='__main__':main()
