from pathlib import Path
import json,shutil,struct,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[1]
BASE=Path('E:/Codex/Work/saixian-sync-61626e2-20261029/repository/5.0project')
def main():
 vendor=ROOT/'vendor';vendor.mkdir(exist_ok=True)
 for name in ['video_pll.v','dual_still_reset_sync.v','hdmi_minimal_tx.v','hdmi_phy_warpper.v','lane_lvds_10_1.v']:
  shutil.copy2(BASE/'src/board_a/user_source/hdl_source'/name,vendor/name)
 for name in ['sd_card_top.v','sd_card_sec_read_write.v','sd_card_cmd.v','spi_master.v']:
  shutil.copy2(BASE/'common/photo_sd'/name,vendor/name)
 td=ROOT/'td_project';td.mkdir(exist_ok=True)
 names=[p for p in sorted((ROOT/'rtl').glob('*.v'))]+list(sorted(vendor.glob('*.v')))
 files=''.join('<File Path="'+p.relative_to(ROOT).as_posix().replace('rtl/','../rtl/').replace('vendor/','../vendor/')+'"><FileInfo><Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/><Attr Name="BelongTo" Val="design_1"/></FileInfo></File>' for p in names)
 template=(BASE/'src/board_a/td_project/PHOTO_BOARD_A.al').read_text(encoding='utf-8-sig')
 import re
 template=re.sub(r'<Source_Files>.*?</Source_Files>','<Source_Files><Verilog>'+files+'</Verilog></Source_Files>',template,flags=re.S)
 template=template.replace('PHOTO_BOARD_A','TEXT_DEMO_J1').replace('top_photo_a','top_text_demo')
 template=re.sub(r'Path="E:/[^"]+"','Path="'+td.as_posix()+'"',template,count=1)
 from xml.dom import minidom
 dom=minidom.parseString(template)
 for index,node in enumerate(dom.getElementsByTagName('File'),1):
  info=node.getElementsByTagName('FileInfo')[0];attr=dom.createElement('Attr');attr.setAttribute('Name','CompileOrder');attr.setAttribute('Val',str(index));info.appendChild(attr)
 (td/'TEXT_DEMO_J1.al').write_text(dom.toprettyxml(indent='    '),encoding='utf-8')
 pins={'clk':'R7','hmi_uart_rx':'D14','hmi_uart_tx':'G11','sd_ncs':'A12','sd_dclk':'A14','sd_miso':'B14','sd_mosi':'A13','HDMI_CLK_P':'K1','HDMI_D2_P':'B3','HDMI_D1_P':'E3','HDMI_D0_P':'F5','HDMI_DDC_SCL':'P1','HDMI_DDC_SDA':'R1'}
 (td/'pins.adc').write_text('\n'.join('set_pin_assignment { '+k+' } { LOCATION = '+v+'; IOSTANDARD = '+('LVDS33' if k in ['HDMI_CLK_P','HDMI_D2_P','HDMI_D1_P','HDMI_D0_P'] else 'LVCMOS33')+'; }' for k,v in pins.items()),encoding='ascii')
 (td/'timing.sdc').write_text('create_clock -name clk -period 20.000 [get_ports {clk}]\nderive_clocks\nset_false_path -to [get_regs -nowarn {uart/m}]\nset_false_path -from [get_regs -nowarn {reset_video/sync_ff*}] -to [get_pins -nowarn {*.sr}]\n',encoding='ascii')
 (td/'build.tcl').write_text('set alRun phy_1\nset device_name eagle_s20.db\nset package_name EG4S20BG256\nset prj_name TEXT_DEMO_J1\nset top_model_name top_text_demo\nset ADCList {pins.adc}\nset SDCList {timing.sdc}\nset IpSDCList {}\nset start_step read_design\nset end_step bitgen\nset area_option -packarea\nset arr_filter false\nset drHoldFix on\nset phyWildParams {place seed 17}\nsource {C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl}\n',encoding='ascii')
 print('Prepared',len(names),'sources')
if __name__=='__main__':main()
