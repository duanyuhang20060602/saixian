`timescale 1ns/1ps
module tb;
reg clk=0;
reg rst=0;
reg frame_tick=0;
reg de_i=0;
reg [9:0] x_i=0;
reg [8:0] y_i=0;
reg [23:0] rgb_in_i=0;
reg display_valid=0;
reg [2:0] loading_phase=0;
reg [3:0] state=0;
reg [1:0] project_id=0;
reg [6:0] minutes=0;
reg [5:0] seconds=0;
reg [3:0] countdown_value=0;
reg [10:0] ticker_x=0;
reg [4:0] ticker_text_length=0;
reg [4:0] title_text_length=0;
reg font_ready=0;
reg [15:0] font_bits=0;
reg [15:0] source_width_bcd=0;
reg [15:0] source_height_bcd=0;
reg [2:0] error_code=0;
reg [6:0] visual_height=0;
reg [6:0] visual_peak=0;
reg [31:0] visual_wave=0;
reg visual_fft_valid=0;
reg visual_wave_valid=0;
reg waveform_mode=0;
reg settings_mode=0;
reg [2:0] setting_item=0;
reg [3:0] volume_setting=0;
reg [3:0] brightness_setting=0;
reg [3:0] contrast_setting=0;
reg [1:0] sharpness_setting=0;
reg [3:0] saturation_setting=0;
reg invert_setting=0;
reg vintage_setting=0;
reg [1:0] enhancement_setting=0;
wire [23:0] rgb,rgb_ref;wire [10:0] address,address_ref;
saixian_osd_overlay dut(.clk(clk),.rst(rst),.frame_tick(frame_tick),.de_i(de_i),.x_i(x_i),.y_i(y_i),.rgb_in_i(rgb_in_i),.display_valid(display_valid),.loading_phase(loading_phase),.state(state),.project_id(project_id),.minutes(minutes),.seconds(seconds),.countdown_value(countdown_value),.ticker_x(ticker_x),.ticker_text_length(ticker_text_length),.title_text_length(title_text_length),.font_ready(font_ready),.font_bits(font_bits),.source_width_bcd(source_width_bcd),.source_height_bcd(source_height_bcd),.error_code(error_code),.visual_height(visual_height),.visual_peak(visual_peak),.visual_wave(visual_wave),.visual_fft_valid(visual_fft_valid),.visual_wave_valid(visual_wave_valid),.waveform_mode(waveform_mode),.settings_mode(settings_mode),.setting_item(setting_item),.volume_setting(volume_setting),.brightness_setting(brightness_setting),.contrast_setting(contrast_setting),.sharpness_setting(sharpness_setting),.saturation_setting(saturation_setting),.invert_setting(invert_setting),.vintage_setting(vintage_setting),.enhancement_setting(enhancement_setting),.font_addr(address),.rgb_out(rgb));
saixian_osd_overlay_reference reference(.clk(clk),.rst(rst),.frame_tick(frame_tick),.de_i(de_i),.x_i(x_i),.y_i(y_i),.rgb_in_i(rgb_in_i),.display_valid(display_valid),.loading_phase(loading_phase),.state(state),.project_id(project_id),.minutes(minutes),.seconds(seconds),.countdown_value(countdown_value),.ticker_x(ticker_x),.ticker_text_length(ticker_text_length),.title_text_length(title_text_length),.font_ready(font_ready),.font_bits(font_bits),.source_width_bcd(source_width_bcd),.source_height_bcd(source_height_bcd),.error_code(error_code),.visual_height(visual_height),.visual_peak(visual_peak),.visual_wave(visual_wave),.visual_fft_valid(visual_fft_valid),.visual_wave_valid(visual_wave_valid),.waveform_mode(waveform_mode),.settings_mode(settings_mode),.setting_item(setting_item),.volume_setting(volume_setting),.brightness_setting(brightness_setting),.contrast_setting(contrast_setting),.sharpness_setting(sharpness_setting),.saturation_setting(saturation_setting),.invert_setting(invert_setting),.vintage_setting(vintage_setting),.enhancement_setting(enhancement_setting),.font_addr(address_ref),.rgb_out(rgb_ref));
always #5 clk=~clk;
integer checks=0,frame,yy,xx,k;
reg [31:0] random_state=32'hd59e427a;
function [31:0] random_word;input dummy;begin
 random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);
 random_word=random_state;
end endfunction
always @(posedge clk)begin
 #1;
 if(rgb!==rgb_ref || address!==address_ref)begin
  $display("mismatch check=%0d xy=%0d,%0d mode=%0d rgb=%h ref=%h font=%h ref=%h",checks,x_i,y_i,waveform_mode,rgb,rgb_ref,address,address_ref);
  $fatal(1,"visual plot retiming changes pixels or font timing");
 end
 checks=checks+1;
end
initial begin
 rst=1;repeat(3)@(negedge clk);rst=0;
 display_valid=1;font_ready=1;font_bits=16'h9249;
 for(frame=0;frame<4;frame=frame+1)begin
  waveform_mode=frame==1||frame==2;frame_tick=1;
  @(negedge clk);frame_tick=0;
  for(yy=0;yy<480;yy=yy+1)for(xx=0;xx<640;xx=xx+1)begin
   x_i=xx;y_i=yy;de_i=1;rgb_in_i=random_word(1'b0);
   visual_height=random_word(1'b0);visual_peak=random_word(1'b0);visual_wave=random_word(1'b0);
   visual_fft_valid=random_word(1'b0);visual_wave_valid=random_word(1'b0);
   @(negedge clk);
  end
 end
 for(k=0;k<50000;k=k+1)begin
  rgb_in_i=random_word(1'b0);
display_valid=random_word(1'b0);
loading_phase=random_word(1'b0);
state=random_word(1'b0);
project_id=random_word(1'b0);
minutes=random_word(1'b0);
seconds=random_word(1'b0);
countdown_value=random_word(1'b0);
ticker_x=random_word(1'b0);
ticker_text_length=random_word(1'b0);
title_text_length=random_word(1'b0);
font_ready=random_word(1'b0);
font_bits=random_word(1'b0);
source_width_bcd=random_word(1'b0);
source_height_bcd=random_word(1'b0);
error_code=random_word(1'b0);
visual_height=random_word(1'b0);
visual_peak=random_word(1'b0);
visual_wave=random_word(1'b0);
visual_fft_valid=random_word(1'b0);
visual_wave_valid=random_word(1'b0);
waveform_mode=random_word(1'b0);
settings_mode=random_word(1'b0);
setting_item=random_word(1'b0);
volume_setting=random_word(1'b0);
brightness_setting=random_word(1'b0);
contrast_setting=random_word(1'b0);
sharpness_setting=random_word(1'b0);
saturation_setting=random_word(1'b0);
invert_setting=random_word(1'b0);
vintage_setting=random_word(1'b0);
enhancement_setting=random_word(1'b0);
  x_i=random_word(1'b0);y_i=random_word(1'b0);de_i=random_word(1'b0);frame_tick=(k%103==0);rst=(k%4093==0);
  @(negedge clk);
 end
 rst=0;repeat(8)@(negedge clk);
 $display("PASS visual plot retiming: %0d exact RGB/font comparisons, complete spectrum/waveform rasters, dynamic metadata, settings, event UI and reset",checks);$finish;
end
endmodule
