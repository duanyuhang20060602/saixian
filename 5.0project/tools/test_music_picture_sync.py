"""Exercise the actual A top-level settings, transition trigger and SPI track state.

PLLs, SDRAM and unrelated rendering use inert port shells; the menu controller,
UART/pointer, transition page event and audio/SPI/FIFO logic are real.
"""
from pathlib import Path
import argparse,hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);a=ap.parse_args()
 out=a.out.resolve();out.mkdir(parents=True,exist_ok=True)
 text=(ROOT/'common/top_photo_a.v').read_text();real={'photo_key_hold','saixian_hmi_uart','photo_touchpad','photo_pointer_overlay','photo_unified_settings_controller','photo_transition_page_event','photo_audio_spi_a'};shells={}
 for m in re.finditer(r'^\s*([a-z]\w*_\w+)\s*(?:#\((.*?)\))?\s+(\w+)\s*\((.*?)\);',text,re.M|re.S):
  module,parameters,instance,ports=m.groups()
  if module in real or module=='module':continue
  names=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',ports)));params=list(dict.fromkeys(re.findall(r'\.(\w+)\s*\(',parameters or '')))
  if module in shells:
   names=list(dict.fromkeys(re.findall(r'input (\w+)',shells[module])+names));params=list(dict.fromkeys(re.findall(r'parameter (\w+)',shells[module])+params))
  if names:shells[module]='module '+module+(' #('+','.join('parameter '+p+'=0' for p in params)+')' if params else '')+'('+','.join('input '+p for p in names)+'); endmodule'
 (out/'hardware_shells.v').write_text('\n'.join(shells.values()))
 bench=r'''`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg active=0,boot=0,result=0,award=0,loading=0,carousel=1,display=1,bg=1;reg[2:0] image=0,count=3,tracks=3;
reg[3:0] presses=0;integer switches=0,pages=0,i;reg[2:0] saved;reg[7:0] epoch;
top_photo_a dut(.clk(clk),.key(4'hf),.hmi_uart_rx(1'b1));
initial begin
 force dut.pixel_clk=clk;force dut.rst_pixel=rst;force dut.blank_start=1'b1;
 force dut.presses=presses;force dut.boot_active=boot;force dut.result_busy=result;force dut.carousel_mode=carousel;
 force dut.award_active=award;force dut.award_loading=loading;force dut.display_valid=display;force dut.current=image;force dut.count=count;
 force dut.transition_active=active;force dut.transition_mode=5'd1;force dut.bg_music_enable=bg;
 force dut.audio_link.track_count=tracks;force dut.audio_link.spi_miso=1'b0;force dut.cue_event=4'd0;
 force dut.volume=4'd5;force dut.edge_valid=1'b0;force dut.effect_valid=1'b0;force dut.auto_valid=1'b0;
 force dut.audio_view_valid=1'b0;force dut.setting_valid=1'b0;force dut.reset_defaults=1'b0;
 force dut.pointer_row_event=1'b0;force dut.pointer_menu_event=1'b0;force dut.hmi_music_next=1'b0;
end
always @(posedge clk)if(!rst)begin if(dut.audio_link.change_track)switches=switches+1;if(dut.page_turn_cue)pages=pages+1;end
task turn;input integer cycles;begin
 @(negedge clk);active=1;repeat(cycles)@(negedge clk);active=0;repeat(5)@(negedge clk);
end endtask
task press;input[3:0] mask;begin presses=mask;@(negedge clk);presses=0;repeat(3)@(negedge clk);end endtask
task sync;input enable;begin
 press(4'b0100);if(!dut.settings_mode)$fatal(1,"menu entry");
 for(i=0;i<14;i=i+1)press(4'b0001);
 if(dut.setting_item!=14)$fatal(1,"sync row unreachable");
 press(enable ? 4'b1000:4'b0010);
 if(dut.music_sync_enable!==enable)$fatal(1,"sync setting");
 press(4'b0001);if(dut.setting_item!=0)$fatal(1,"menu wrap");
 press(4'b0100);if(dut.settings_mode)$fatal(1,"menu exit");
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(12)@(negedge clk);
 if(dut.music_sync_enable)$fatal(1,"sync must default off");
 turn(10);if(switches!=0)$fatal(1,"default playback interrupted");
 sync(1);turn(10);if(switches!=1 || dut.music_index!=1)$fatal(1,"one accepted transition must advance one track");
 // A held transition level must not keep incrementing. Track wrap uses the existing catalog.
 turn(20);turn(1);if(switches!=3 || dut.music_index!=0)$fatal(1,"track wrap or duplicate transition");
 // Navigation requests and load failures without a real transition cannot skip a track.
 saved=dut.music_index;epoch=dut.music_epoch;press(4'b0001);repeat(10)@(negedge clk);
 if(dut.music_index!=saved || dut.music_epoch!=epoch)$fatal(1,"request switched music before image availability");
 tracks=1;turn(5);if(switches!=3)$fatal(1,"single track reset");tracks=0;turn(5);if(switches!=3)$fatal(1,"empty catalog reset");tracks=3;
 boot=1;turn(2);boot=0;result=1;turn(2);result=0;award=1;turn(2);award=0;loading=1;turn(2);loading=0;
 display=0;turn(2);display=1;carousel=0;turn(2);carousel=1;bg=0;turn(2);bg=1;
 if(switches!=3)$fatal(1,"inactive scene switched music");
 sync(0);turn(3);if(switches!=3)$fatal(1,"disabled sync switched music");
 press(4'b0010);if(switches!=4)$fatal(1,"manual music-next regressed");
 sync(1);force dut.reset_defaults=1'b1;@(negedge clk);force dut.reset_defaults=1'b0;
 if(dut.music_sync_enable)$fatal(1,"reset defaults did not clear sync");
 $display("PASS actual top wiring: sync menu on/off/default/reset, one switch per accepted transition, wrap, single/zero tracks, request/failure isolation, boot/result/award/loading/event/music gates, manual music-next");$finish;
end
initial begin #1000000;$fatal(1,"sync timeout");end
endmodule
'''
 (out/'sync.v').write_text(bench,encoding='ascii')
 names=['common/top_photo_a.v','common/photo_unified_settings_controller.v','common/saixian_hmi_uart.v','common/photo_touchpad.v','common/photo_audio_link.v','common/photo_audio_features.v']
 files=[out/'sync.v',out/'hardware_shells.v']+[ROOT/n for n in names];iv=ROOT.parents[1]/'.tools/iverilog/bin/iverilog.exe';binary=out/'sync.vvp'
 r=subprocess.run([str(iv),'-g2012','-DERAM_SIM','-s','tb','-o',str(binary),*map(str,files)],cwd=out,capture_output=True,text=True);log=r.stdout+r.stderr
 if r.returncode==0:r=subprocess.run([str(iv.with_name('vvp.exe')),str(binary)],cwd=out,capture_output=True,text=True,timeout=120);log+=r.stdout+r.stderr
 (out/'sync.log').write_text(log,encoding='utf-8');print(log[-4000:]);passed=r.returncode==0 and 'PASS ' in log
 (out/'results.json').write_text(json.dumps({'passed':passed,'scope':'real top/settings/page event/SPI track logic; external hardware shells','inputs_sha256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}},indent=2),encoding='utf-8');assert passed
if __name__=='__main__':main()
