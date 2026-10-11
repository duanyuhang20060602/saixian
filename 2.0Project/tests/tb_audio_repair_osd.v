`timescale 1ns/1ps
module tb_audio_repair_osd;
reg clk=0,rst=1,en=0;
reg [9:0] x=0;reg [8:0] y=0;
wire [23:0] rgb;
integer output_file,px,py;
reg [2047:0] filename;
always #5 clk=~clk;
saixian_osd_overlay dut(
    .clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(1'b1),.x_i(x),.y_i(y),.rgb_in_i(24'h606060),
    .display_valid(1'b1),.loading_phase(3'd0),.state(4'd0),.project_id(2'd0),.minutes(7'd0),.seconds(6'd0),
    .countdown_value(4'd0),.ticker_x(10'd0),.source_width_bcd(16'd0),.source_height_bcd(16'd0),
    .error_code(3'd0),.transition_active(1'b0),.transition_level(6'd0),.audio_level(8'd0),
    .spectrum_active(1'b0),.spectrum_tone_bin(5'd0),.settings_mode(1'b1),.setting_item(4'd8),
    .audio_repair_setting(en),.volume_setting(4'd5),.brightness_setting(4'd4),.contrast_setting(4'd4),
    .sharpness_setting(2'd1),.saturation_setting(4'd4),.invert_setting(1'b0),.vintage_setting(1'b0),
    .enhancement_setting(2'd1),.audio_sample_valid(1'b0),.audio_sample(8'd0),.visual_mode(1'b0),
    .visual_height(7'd0),.visual_peak(7'd0),.visual_wave(32'd0),.visual_fft_valid(1'b0),.visual_wave_valid(1'b0),.rgb_out(rgb));
task pixel;input integer xx,yy;input [23:0] wanted;begin
    x=xx;y=yy;repeat(6) @(negedge clk);
    if(rgb!==wanted) $fatal(1,"repair OSD pixel (%d,%d) got %h wanted %h",xx,yy,rgb,wanted);
end endtask
initial begin
    repeat(4) @(negedge clk);rst=0;
    pixel(300,158,24'h35445a);en=1;pixel(300,158,24'h34d6ff);
    // Rows 2..4 must not show stale values from the preceding menu page.
    pixel(300,214,24'h101827);pixel(300,270,24'h101827);pixel(300,326,24'h101827);
    x=128;y=144;repeat(6) @(negedge clk);if(dut.glyph_id!=74) $fatal(1,"missing 音");
    x=160;repeat(6) @(negedge clk);if(dut.glyph_id!=101) $fatal(1,"missing 频");
    x=192;repeat(6) @(negedge clk);if(dut.glyph_id!=102) $fatal(1,"missing 修");
    x=224;repeat(6) @(negedge clk);if(dut.glyph_id!=85) $fatal(1,"missing 复");
    if($value$plusargs("PPM=%s",filename)) begin
        output_file=$fopen(filename,"w");$fwrite(output_file,"P3\n640 480\n255\n");
        for(py=0;py<480;py=py+1) for(px=0;px<640;px=px+1) begin
            x=px;y=py;repeat(6) @(negedge clk);
            $fwrite(output_file,"%d %d %d\n",rgb[23:16],rgb[15:8],rgb[7:0]);
        end
        $fclose(output_file);
    end
    $display("PASS repair OSD: full Chinese label, on/off bar, correct value and blank unused rows");$finish;
end
endmodule
// Production font data, with the same synchronous RAM read latency.
module saixian_font_rom(input clk,input [6:0] glyph_id,input [3:0] row,output reg [15:0] bits);
reg [15:0] memory[0:2047];
reg [2047:0] font_file;
initial begin
    for(integer i=0;i<2048;i=i+1) memory[i]=0;
    if($value$plusargs("FONT=%s",font_file)) $readmemh(font_file,memory);
end
always @(posedge clk) bits<=memory[{glyph_id,row}];
endmodule
