from pathlib import Path
import math,shutil,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
PARENT=ROOT.parent

def main():
    project=ROOT/'project'
    selected=list((ROOT/'tf_assets').glob('*.AUD'))
    if len(selected)==1:
        (ROOT/'tests/selected_audio_header.hex').write_text(''.join(f'{b:02x}\n' for b in selected[0].read_bytes()[:512]),encoding='ascii')
    roms={
      'water_fx_recip.hex':[round(262144/max(8,k)) for k in range(257)]+[k*k for k in range(1,256)],
      'water_fx_wave.hex':[round(32*math.sin(2*math.pi*k/64))&255 for k in range(64)],
      'water_flip.hex':[round(262144/max(16,abs(256-2*p))) for p in range(257)],
      'water_strip.hex':[round(24*math.sin(math.pi*y/90)) for y in range(90)],
      'water_roll.hex':[(round(96*2/math.pi*math.acos(min(1,i*4/128))) | (round(24*(1-i/31)**1.5)<<8) | ((1 if i in (0,1,2,3) else 0)<<13)) for i in range(32)],
      'water_tone.hex':[round(4096*math.sin(i*2*math.pi/48))&65535 for i in range(48)],
      'water_sine.hex':[round(math.sin(i*2*math.pi/512)*4096)&65535 for i in range(512)],
      'water_inverse.hex':[0]+[round(65536/i) for i in range(1,2048)],
      'water_wave.hex':[round(-(i-96)/25*math.exp(-.5*((i-96)/25)**2)*14*256)&65535 if i<=192 else 0 for i in range(256)],
      'water_edge.hex':[round(max(0,1-i/76)**2.2*96) for i in range(128)]}
    for name,values in roms.items():
        width=5 if name=='water_inverse.hex' else 2 if name in ('water_edge.hex','water_strip.hex','water_fx_wave.hex') else 4
        text=''.join(f'{v:0{width}x}\n' for v in values)
        for dest in [project,ROOT/'rtl',ROOT/'tests',PARENT]: (dest/name).write_text(text,encoding='ascii')
    for dest in [project,PARENT,ROOT/'vendor']:shutil.copy2(ROOT/'vendor/global_def.v',dest/'water_global_def.v')
    vendor=['sd_card_top.v','sd_card_cmd.v','sd_card_sec_read_write.v','spi_master.v',
            'audio_arc_calculate.v','hdmi_phy_wrapper.v','lane_lvds_10_1.v','hdmi_audio.enc.v']
    files=list(sorted((ROOT/'rtl').glob('*.v')))
    files += [ROOT/'vendor'/x for x in ['board_helpers.v','saixian_key_debounce.v','bmp_read.v','sd_card_bmp.v','saixian_media_header.v',
            'frame_fifo_write.v','frame_read_write.v','video_delay.v','sdram.v','afifo_16_32_256.v','afifo_32_16_256.v',
            'sdr_as_ram.enc.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v']]
    files += [PARENT/'vendor'/x for x in vendor]
    files += [PARENT/'rtl'/'fluid_plls.v',PARENT/'rtl'/'fluid_rgb_limited.v']
    # fluid_plls defines an unused legacy system PLL; synthesis removes it.
    template=ET.parse(PARENT/'project'/'FLUID_SINGLE.al').getroot()
    for gui in [False,True]:
        import copy,os
        root=copy.deepcopy(template);directory=PARENT if gui else project
        root.set('Path',directory.as_posix());root.find('Name').text='WATER_SINGLE'
        sf=root.find('Source_Files');sf.clear();v=ET.SubElement(sf,'Verilog')
        for i,p in enumerate(files):
            f=ET.SubElement(v,'File',Path=os.path.relpath(p,directory).replace('\\','/'));info=ET.SubElement(f,'FileInfo')
            for k,val in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(i+1))]:ET.SubElement(info,'Attr',Name=k,Val=val)
        for tag,name in [('ADC_FILE','pins.adc'),('SDC_FILE','timing.sdc')]:
            f=ET.SubElement(ET.SubElement(sf,tag),'File',Path=('water_single/project/' if gui else '')+name);info=ET.SubElement(f,'FileInfo')
            for k,val in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','constraint_1'),('CompileOrder','2' if tag=='ADC_FILE' else '1')]:ET.SubElement(info,'Attr',Name=k,Val=val)
        for tag in ['LABEL','MODULE']:root.find('TOP_MODULE/'+tag).text='top_water_single'
        ET.indent(root);ET.ElementTree(root).write(directory/'WATER_SINGLE.al',encoding='UTF-8',xml_declaration=True)
    print(PARENT/'WATER_SINGLE.al')

if __name__=='__main__':main()
