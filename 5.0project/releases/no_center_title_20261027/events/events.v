`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg[9:0] x=20;reg[8:0] y=16;reg[1:0] project=0;wire[23:0] rgb;wire[23:0] rgb_ref;wire[10:0] addr,addr_ref;integer i,j,k,checks=0;
reg[4:0] length=0;reg[10:0] phase=200;reg[3:0] state=0;
saixian_osd_overlay #(.HIDE_CAROUSEL_LABEL(1),.CAROUSEL_TITLE(0),.SHOW_SOURCE_RESOLUTION(0),.SHARED_TITLE(1),.INDEPENDENT_TEXT(1),.EMPTY_TEXT_BLANK(1)) d(
 .clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.loading_phase(3'd0),.state(state),.project_id(project),.minutes(7'd0),.seconds(6'd0),.countdown_value(4'd0),
 .ticker_x(phase),.ticker_text_length(5'd0),.title_text_length(length),.font_bits(16'hffff),.font_ready(1'b1),.font_addr(addr),
 .source_width_bcd(16'd0),.source_height_bcd(16'd0),.error_code(3'd0),.visual_height(7'd0),.visual_peak(7'd0),.visual_wave(32'd0),
 .visual_fft_valid(1'b0),.visual_wave_valid(1'b0),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd4),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),
 .invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(rgb));
saixian_osd_overlay_reference #(.CAROUSEL_TITLE(1),.SHOW_SOURCE_RESOLUTION(0),.SHARED_TITLE(1),.INDEPENDENT_TEXT(1),.EMPTY_TEXT_BLANK(1)) r(
 .clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.loading_phase(3'd0),.state(state),.project_id(project),.minutes(7'd0),.seconds(6'd0),.countdown_value(4'd0),
 .ticker_x(phase),.ticker_text_length(5'd0),.title_text_length(length),.font_bits(16'hffff),.font_ready(1'b1),.font_addr(addr_ref),
 .source_width_bcd(16'd0),.source_height_bcd(16'd0),.error_code(3'd0),.visual_height(7'd0),.visual_peak(7'd0),.visual_wave(32'd0),
 .visual_fft_valid(1'b0),.visual_wave_valid(1'b0),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd4),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),
 .invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(rgb_ref));
initial begin
 repeat(5)@(negedge clk);rst=0;length=16;
 for(k=1;k<=8;k=k+1)begin
  state=k;
  for(j=16;j<48;j=j+1)for(i=180;i<620;i=i+1)begin
   @(negedge clk);x=i;y=j;repeat(5)@(negedge clk);
   if(rgb!==rgb_ref || addr!==addr_ref)$fatal(1,"event state changed: state%0d xy%0d,%0d",k,x,y);
   checks=checks+1;
  end
 end
 $display("PASS preserved competition labels and clock: %0d pixels/address pairs, all eight event states",checks);$finish;
end
endmodule
