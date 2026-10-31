`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,mode=1;always #5 clk=~clk;
reg[9:0] x=0;reg[8:0] y=0;reg[4:0] length=16;reg[15:0] bitmap=16'hffff;
wire[10:0] address;wire[23:0] rgb;
saixian_osd_overlay #(.TYPED_CAROUSEL(1),.INDEPENDENT_TEXT(1),.SHARED_TITLE(1),.EMPTY_TEXT_BLANK(1)) dut(
 .typed_text_mode(mode),.clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.loading_phase(3'd0),.state(4'd0),.project_id(2'd0),.minutes(7'd0),.seconds(6'd0),.countdown_value(4'd0),.ticker_x(11'd0),
 .ticker_text_length(length),.title_text_length(5'd0),.font_ready(1'b1),.font_addr(address),.font_bits(bitmap),.source_width_bcd(16'd0),.source_height_bcd(16'd0),.error_code(3'd0),
 .visual_height(7'd0),.visual_peak(7'd0),.visual_wave(32'd0),.visual_fft_valid(1'b0),.visual_wave_valid(1'b0),.waveform_mode(1'b0),.settings_mode(1'b0),.setting_item(3'd0),
 .volume_setting(4'd4),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),.saturation_setting(4'd4),.invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),.rgb_out(rgb));
task sample;input integer px,py;begin x=px;y=py;repeat(7)@(negedge clk);end endtask
integer c,r,col;
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(c=0;c<16;c=c+1)for(r=0;r<16;r=r+1)for(col=0;col<16;col=col+1)begin
  sample(64+c*32+col*2,432+r*2);
  if(!dut.text_region || dut.glyph_id!=112+c || dut.font_row!=r || dut.font_col!=col || rgb!==24'hffd166)$fatal(1,"full-line cell mapping/pixel mismatch %d/%d/%d",c,r,col);
 end
 sample(63,432);if(dut.text_region)$fatal(1,"left boundary");sample(576,432);if(dut.text_region)$fatal(1,"right boundary");
 bitmap=0;sample(64,432);if(rgb!==24'h091a2b)$fatal(1,"blink transparency to the original dimmed footer");
 length=3;bitmap=16'hffff;sample(159,432);if(!dut.text_region)$fatal(1,"short line tail");sample(160,432);if(dut.text_region)$fatal(1,"short line boundary");
 mode=0;sample(64,432);if(dut.text_region)$fatal(1,"legacy phase changed");
 $display("PASS full 16-character typed line, all 4096 cells, glyph/row/column mapping, gold pixels, blink transparency, shortened bounds and original ticker phase");$finish;
end
endmodule
