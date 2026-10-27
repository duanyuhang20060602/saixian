`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg[9:0] x=20;reg[8:0] y=16;reg[1:0] project=0;wire[23:0] rgb;integer i,j,k,checks=0;
reg[4:0] length=0;reg[10:0] phase=200;reg[3:0] state=0;
saixian_osd_overlay #(.CAROUSEL_TITLE(1),.SHOW_SOURCE_RESOLUTION(0),.SHARED_TITLE(1),.INDEPENDENT_TEXT(1),.EMPTY_TEXT_BLANK(1)) d(
 .clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.loading_phase(3'd0),.state(state),.project_id(project),.minutes(7'd0),.seconds(6'd0),.countdown_value(4'd0),
 .ticker_x(phase),.ticker_text_length(5'd0),.title_text_length(length),.font_bits(16'hffff),.font_ready(1'b1),
 .source_width_bcd(16'd0),.source_height_bcd(16'd0),.error_code(3'd0),.visual_height(7'd0),.visual_peak(7'd0),.visual_wave(32'd0),
 .visual_fft_valid(1'b0),.visual_wave_valid(1'b0),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd4),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),
 .invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(rgb));
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(k=0;k<4;k=k+1)begin
  project=k;
  for(j=0;j<32;j=j+1)for(i=0;i<128;i=i+1)begin
   @(negedge clk);x=20+i;y=16+j;repeat(5)@(negedge clk);
   if(rgb!==24'h091a2b)$fatal(1,"missing title displayed fallback text project%0d xy%0d,%0d",k,x,y);checks=checks+1;
  end
  for(j=0;j<32;j=j+1)for(i=0;i<640;i=i+1)begin
   @(negedge clk);x=i;y=432+j;repeat(5)@(negedge clk);
   if(rgb!==24'h091a2b)$fatal(1,"missing ticker displayed fallback text");checks=checks+1;
  end
  for(j=0;j<32;j=j+1)for(i=0;i<192;i=i+1)begin
   @(negedge clk);x=180+i;y=16+j;repeat(5)@(negedge clk);
   if(rgb!==24'h091a2b)$fatal(1,"missing center title displayed fixed state label");checks=checks+1;
  end
 end
 length=16;
 for(k=0;k<16;k=k+1)begin
  @(negedge clk);x=180;y=16;phase=512-k*32;repeat(5)@(negedge clk);
  if(d.glyph_id!==96+k || !d.text_region || d.font_col!==0 || d.font_row!==0)$fatal(1,"center title long-glyph mapping %0d",k);
 end
 length=3;
 for(k=0;k<3;k=k+1)begin
  @(negedge clk);x=180+32*k;y=16;phase=700;repeat(5)@(negedge clk);
  if(d.glyph_id!==96+k)$fatal(1,"short center title scrolled");
 end
 @(negedge clk);state=6;x=180;repeat(5)@(negedge clk);
 if(d.glyph_id!==70)$fatal(1,"custom title replaced running state");
 $display("PASS blank missing SD title/ticker/center: %0d pixels, four projects; all 16 shared center glyphs, static short title and preserved running state",checks);$finish;
end
endmodule
