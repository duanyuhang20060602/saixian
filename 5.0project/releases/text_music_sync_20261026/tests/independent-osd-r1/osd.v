`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;
reg [9:0] x=0;reg [8:0] y=0;reg [3:0] state=0;reg [1:0] project=0;
reg [10:0] phase=0;reg [4:0] length=0,ticker_length=0;wire [10:0] addr,old_addr;wire [23:0] rgb,old_rgb;
saixian_osd_overlay #(.SHARED_TITLE(1),.INDEPENDENT_TEXT(1)) dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.loading_phase(3'd0),.state(state),.project_id(project),.minutes(7'd12),.seconds(6'd34),.countdown_value(4'd3),
 .ticker_x(phase),.ticker_text_length(ticker_length),.title_text_length(length),.font_ready(1'b1),.font_addr(addr),.font_bits(16'ha55a),
 .source_width_bcd(16'h1280),.source_height_bcd(16'h0720),.error_code(3'd0),.visual_height(7'd32),.visual_peak(7'd40),.visual_wave(32'h12345678),
 .visual_fft_valid(1'b1),.visual_wave_valid(1'b1),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd4),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),
 .invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(rgb));
saixian_osd_overlay_before golden(.clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.loading_phase(3'd0),.state(state),.project_id(project),.minutes(7'd12),.seconds(6'd34),.countdown_value(4'd3),
 .ticker_x(phase),.ticker_text_length(ticker_length),.title_text_length(length),.font_ready(1'b1),.font_addr(old_addr),.font_bits(16'ha55a),
 .source_width_bcd(16'h1280),.source_height_bcd(16'h0720),.error_code(3'd0),.visual_height(7'd32),.visual_peak(7'd40),.visual_wave(32'h12345678),
 .visual_fft_valid(1'b1),.visual_wave_valid(1'b1),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd4),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),
 .invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(old_rgb));
integer i,j,k;
task sample;input integer sx,sy,p;begin
 @(negedge clk);x=sx;y=sy;phase=p;repeat(3)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;repeat(8)@(negedge clk);
 for(k=0;k<2;k=k+1)begin
  project=k==0 ? 0:3;
  for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin
   @(negedge clk);x=i;y=j;phase=(i+j)%865;
   if(rgb!==old_rgb || addr!==old_addr)$fatal(1,"fallback changed %0d,%0d",i,j);
  end
 end
 length=16;ticker_length=6;
 for(k=0;k<16;k=k+1)begin
  sample(20,16,512-k*32);
  if(!dut.text_region || dut.glyph_id!=96+k || dut.font_col!=0 || dut.font_row!=0)$fatal(1,"long header glyph %0d absent",k);
 end
 for(k=0;k<6;k=k+1)begin
  sample(0,432,192-k*32);
  if(!dut.text_region || dut.glyph_id!=112+k || dut.font_col!=0 || dut.font_row!=0)$fatal(1,"independent ticker bank %d absent",k);
 end
 // Both labels move right as the single shared position increments.
 sample(100,16,500);i=dut.title_local_x;
 sample(101,16,501);if(dut.title_local_x!=i)$fatal(1,"header movement is not left-to-right");
 sample(100,432,500);i=dut.ticker_local_x;
 sample(101,432,501);if(dut.ticker_local_x!=i)$fatal(1,"ticker movement is not left-to-right");
 length=3;ticker_length=16;
 for(k=0;k<3;k=k+1)begin
  sample(20+k*32,16,0);if(dut.glyph_id!=96+k)$fatal(1,"short header mapping");
  sample(20+k*32,16,700);if(dut.glyph_id!=96+k)$fatal(1,"short header scrolled");
 end
 for(k=0;k<16;k=k+1)begin
  sample(0,432,512-k*32);if(dut.glyph_id!=112+k)$fatal(1,"long ticker changed with short header");
 end
 $display("PASS independent 16/6 and 3/16 title/ticker lengths, all 32 font glyphs, shared phase, short header static, two full fallback rasters unchanged, all 16 shared header/ticker glyphs visible, left-to-right motion, stable short header");$finish;
end
initial begin #10000000;$fatal(1,"OSD timeout");end
endmodule
