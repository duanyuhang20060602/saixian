from pathlib import Path
import xml.etree.ElementTree as ET
import os, re, json
ROOT=Path(__file__).resolve().parents[1]
def write(path,text):
    path.write_text(text,encoding='utf-8',newline='\n')
for role,top in [('board_a','top_photo_a'),('board_b','top_photo_b')]:
    src=ROOT/'projects'/role/'src'
    hdl=src/'user_source/hdl_source'
    if role=='board_a':
        p=hdl/'frame_pixels.v';text=p.read_text(encoding='utf-8')
        text=text.replace('limited({pixel[15:11],pixel[15:13]})','{pixel[15:11],pixel[15:13]}').replace('limited({pixel[10:5],pixel[10:9]})','{pixel[10:5],pixel[10:9]}').replace('limited({pixel[4:0],pixel[4:2]})','{pixel[4:0],pixel[4:2]}')
        write(p,text)
        p=hdl/'hdmi_minimal_tx.v';text=p.read_text(encoding='utf-8')
        if 'VIDEO_DELAY' not in text:
            text=text.replace('VIC=0, EXTERNAL_VIDEO=0','VIC=0, EXTERNAL_VIDEO=0, VIDEO_DELAY=2')
            start=text.index('reg [2:0] mode1,mode2;')
            end=text.index(' wire [2:0] send_mode',start)
            text=text[:start]+'''reg [2:0] mode_pipe [0:VIDEO_DELAY-1];
 reg [1:0] c0_pipe[0:VIDEO_DELAY-1],c1_pipe[0:VIDEO_DELAY-1],c2_pipe[0:VIDEO_DELAY-1];
 reg [3:0] n0_pipe[0:VIDEO_DELAY-1],n1_pipe[0:VIDEO_DELAY-1],n2_pipe[0:VIDEO_DELAY-1];
 integer di;
 always @(posedge clk or posedge rst)begin
  if(rst)begin for(di=0;di<VIDEO_DELAY;di=di+1)begin mode_pipe[di]<=0;c0_pipe[di]<=0;c1_pipe[di]<=0;c2_pipe[di]<=0;n0_pipe[di]<=0;n1_pipe[di]<=0;n2_pipe[di]<=0;end end
  else begin
   mode_pipe[0]<=mode;c0_pipe[0]<={vs,hs};c1_pipe[0]<=ctl1;c2_pipe[0]<=ctl2;
   n0_pipe[0]<=nibble0;n1_pipe[0]<=nibble1;n2_pipe[0]<=nibble2;
   for(di=1;di<VIDEO_DELAY;di=di+1)begin
    mode_pipe[di]<=mode_pipe[di-1];c0_pipe[di]<=c0_pipe[di-1];c1_pipe[di]<=c1_pipe[di-1];c2_pipe[di]<=c2_pipe[di-1];
    n0_pipe[di]<=n0_pipe[di-1];n1_pipe[di]<=n1_pipe[di-1];n2_pipe[di]<=n2_pipe[di-1];
   end
  end
 end
 wire [2:0] mode2=mode_pipe[VIDEO_DELAY-1];
 wire [1:0] ctl02=c0_pipe[VIDEO_DELAY-1],ctl12=c1_pipe[VIDEO_DELAY-1],ctl22=c2_pipe[VIDEO_DELAY-1];
 wire [3:0] ni02=n0_pipe[VIDEO_DELAY-1],ni12=n1_pipe[VIDEO_DELAY-1],ni22=n2_pipe[VIDEO_DELAY-1];
''' + text[end:]
            write(p,text)
    td=src/'td_project';old=next(td.glob('*.al'))
    project=ET.fromstring(old.read_text(encoding='utf-8').replace('P&R','P&amp;R'));tree=ET.ElementTree(project)
    project.set('Path',td.as_posix())
    project.find('Name').text='PHOTO_'+role.upper()
    for tag in ['LABEL','MODULE']:project.find('TOP_MODULE/'+tag).text=top
    verilog=project.find('Source_Files/Verilog')
    paths=[e.get('Path') for e in verilog]
    excluded={'top_board_a.v','top_board_b.v','link_sender.v','dual_still_link_rx.v','sd_card_bmp.v'}
    replacements={p.name for p in (ROOT/'common/photo_sd').glob('*.v')}
    for e in list(verilog):verilog.remove(e)
    paths=[p for p in paths if Path(p).name not in excluded | replacements]
    shared=['photo_color_format.v','photo_uart.v','photo_link.v','photo_control.v','photo_status.v',top+'.v']
    if role=='board_a':shared+=['photo_audio_link.v','photo_audio_features.v','audio_ui/photo_audio_cue_samples.v','audio_ui/saixian_event_controller.v','audio_ui/saixian_osd_overlay.v','audio_ui/saixian_font_rom.v','audio_vendor/audio_arc_calculate.v','audio_vendor/hdmi_1_4b_transmitter_core_wrapper.enc.v','photo_resolution_overlay.v','photo_settings_overlay.v','photo_unified_settings_controller.v','photo_menu_font.v','photo_cached_control_a.v','saixian_transition.v','photo_processing.v','saixian_hmi_uart.v','saixian_key_debounce.v','photo_auto_advance.v']
    else:shared+=['photo_audio_link.v','photo_audio_features.v','audio_ui/photo_audio_cue_samples.v','photo_sd_audio_stream.v','photo_sd_cache.v','photo_processing.v','photo_b_processing.v']
    paths+=['../../../../common/'+p for p in shared]
    if role=='board_b':paths+=['../../../../common/photo_sd/'+p.name for p in (ROOT/'common/photo_sd').glob('*.v')]
    # Imported B al may already list saixian_media_header under SD.
    paths=list(dict.fromkeys(paths))
    for n,p in enumerate(paths,1):
        assert (td/p).is_file(),p
        e=ET.SubElement(verilog,'File',Path=p);info=ET.SubElement(e,'FileInfo')
        for key,val in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(n))]:ET.SubElement(info,'Attr',Name=key,Val=val)
    write(td/('PHOTO_'+role.upper()+'.al'),ET.tostring(project,encoding='unicode').replace('P&amp;R','P&R'))
    write(td/'sources.json',json.dumps(paths,indent=2)+'\n')
    # Preserve TD flow parameters and the tested timing strategy.
    p=td/'build_board.tcl';text=p.read_text(encoding='utf-8')
    text=re.sub(r'set prj_name \{[^}]+\}',f'set prj_name {{PHOTO_{role.upper()}}}',text)
    text=re.sub(r'set top_model_name \{[^}]+\}',f'set top_model_name {{{top}}}',text)
    write(p,text)
    constraints=src/'user_source/constraints_source';pins=next(constraints.glob('*pins.adc'))
    text=pins.read_text(encoding='utf-8')
    if 'control_rx' not in text:
        rx,tx=('F3','H5') if role=='board_a' else ('H5','F3')
        text+=f'\nset_pin_assignment {{ control_rx }} {{ LOCATION = {rx}; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }}\n'
        text+=f'set_pin_assignment {{ control_tx }} {{ LOCATION = {tx}; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }}\n'
        if role=='board_a':
            for n,pin in enumerate(['A2','B2','B1','C1']):text+=f'set_pin_assignment {{ key[{n}] }} {{ LOCATION = {pin}; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }}\n'
            text+='set_pin_assignment { hmi_uart_rx } { LOCATION = D14; IOSTANDARD = LVCMOS33; PULLTYPE = PULLUP; }\nset_pin_assignment { hmi_uart_tx } { LOCATION = G11; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; }\n'
        write(pins,text)
    # Migrate existing generated projects as well as fresh exports.
    text=pins.read_text(encoding='utf-8')
    for signal,pin in [('control_rx','F3' if role=='board_a' else 'H5'),('control_tx','H5' if role=='board_a' else 'F3')]:
        text=re.sub(r'(set_pin_assignment \{ '+signal+r' \} \{ LOCATION = )\w+',r'\g<1>'+pin,text)
    write(pins,text)
    # AUDIO1 uses J2 only. J2-24's obsolete image_ack wire becomes MOSI;
    # current image acceptance/commit is already acknowledged over UART.
    text=re.sub(r'^.*set_pin_assignment.*\{ image_ack \}.*\n','',text,flags=re.M)
    for signal,pin in [('audio_mosi','H3'),('audio_sclk','E2'),('audio_cs','J11'),('audio_miso','J12')]:
        if '{ '+signal+' }' not in text:
            is_output=(role=='board_a' and signal!='audio_miso') or (role=='board_b' and signal=='audio_miso')
            attrs='DRIVESTRENGTH = 8;' if is_output else 'PULLTYPE = PULLUP;'
            text+=f'set_pin_assignment {{ {signal} }} {{ LOCATION = {pin}; IOSTANDARD = LVCMOS33; {attrs} }}\n'
    write(pins,text)
    p=next(constraints.glob('*timing.sdc'));text=p.read_text(encoding='utf-8')
    text='\n'.join(line for line in text.splitlines() if '*diagnostic_meta*' not in line and 'get_regs -nowarn {rx/crc*}' not in line and 'get_regs -nowarn {tx/crc*}' not in line)+'\n'
    text='\n'.join(line for line in text.splitlines() if 'get_ports {image_ack}' not in line)+'\n'
    write(p,text)
    if 'photo CDC' not in text:
        text+='''
# photo CDC: cut only first-stage synchronizers; bundled metadata remains
# stable for the complete transaction. Gray FIFO paths retain IP constraints.
set_false_path -to [get_regs -nowarn {*event_meta* *rx_meta* *fault_meta* *armed_meta* *fin_meta* *key_meta* *sync_key[0]* *key_sync[0]* *write_addr_index_d0* *read_addr_index_d0* *slide_old_d0* *slide_new_d0* *slide_active_d0* *slide_right_d0* *slide_offset_d0* *transition_mode_d0*}]
set_false_path -from [get_ports {control_rx}]
'''
        if role=='board_a':text+='set_false_path -from [get_ports {hmi_uart_rx key[*]}]\n'
        write(p,text)
    if role=='board_b' and '*settings_meta*' not in text:
        text+='set_false_path -to [get_regs -nowarn {*settings_meta* *gain_meta* *processing/ack_meta*}]\n'
        write(p,text)
    text=p.read_text(encoding='utf-8')
    if '# AUDIO1' not in text:
        text+='# AUDIO1: SPI oversampling, cut only async first stages.\n'
        if role=='board_a':
            text+='set_false_path -to [get_regs -nowarn {*spi_miso_meta* *hpd_audio_meta* *audio_diag_meta*}]\n'
            text+='set_output_delay -clock {board_pixel_clk} -max 2.000 [get_ports {audio_sclk audio_cs audio_mosi}]\n'
            text+='set_output_delay -clock {board_pixel_clk} -min 0.500 [get_ports {audio_sclk audio_cs audio_mosi}]\n'
        else:
            text+='set_false_path -to [get_regs -nowarn {*spi_sclk_meta* *spi_cs_meta* *spi_mosi_meta*}]\n'
            text+='set_output_delay -clock {sd_card_clk} -max 2.000 [get_ports {audio_miso}]\n'
            text+='set_output_delay -clock {sd_card_clk} -min 0.500 [get_ports {audio_miso}]\n'
        write(p,text)
    if '*color_meta*' not in text:
        text+='set_false_path -to [get_regs -nowarn {*color_meta* *color_link_meta*}]\n'
        write(p,text)
    write(p,text)
print('Configured independent A/B TD projects.')
