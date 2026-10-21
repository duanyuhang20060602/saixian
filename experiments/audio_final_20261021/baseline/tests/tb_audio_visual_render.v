`timescale 1ns/1ps
module tb_audio_visual_render;
reg clk=0,rst=1,de_i=0;
reg [9:0] x_i=0;
reg [8:0] y_i=0;
reg [23:0] rgb_in_i=24'h808080;
reg visual_mode=0;
reg [6:0] visual_height=28,visual_peak=40;
reg [31:0] visual_wave=32'hf810fc08;
wire [23:0] rgb_out;
reg [23:0] expected[0:3];
integer i,j;
always #5 clk=~clk;
saixian_osd_overlay dut(
    .clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(de_i),.x_i(x_i),.y_i(y_i),.rgb_in_i(rgb_in_i),
    .display_valid(1'b1),.loading_phase(3'd0),.state(4'd0),.project_id(2'd0),.minutes(7'd0),.seconds(6'd0),
    .countdown_value(4'd0),.ticker_x(10'd0),.source_width_bcd(16'd0),.source_height_bcd(16'd0),
    .error_code(3'd0),.transition_active(1'b0),.transition_level(6'd0),.audio_level(8'd0),
    .spectrum_active(1'b0),.spectrum_tone_bin(5'd0),.settings_mode(1'b0),.setting_item(3'd0),
    .volume_setting(4'd5),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1),
    .saturation_setting(4'd4),.invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1),
    .audio_sample_valid(1'b0),.audio_sample(8'd0),.visual_mode(visual_mode),.visual_height(visual_height),
    .visual_peak(visual_peak),.visual_wave(visual_wave),.visual_fft_valid(1'b1),.visual_wave_valid(1'b1),.rgb_out(rgb_out));
task pixel;input [9:0] px;input [8:0] py;input [23:0] wanted;
begin
    x_i=px;y_i=py;de_i=1;repeat(6) @(negedge clk);
    if(rgb_out!==wanted) $fatal(1,"pixel (%d,%d) got=%h expected=%h",px,py,rgb_out,wanted);
end endtask
initial begin
    repeat(4) @(negedge clk);rst=0;repeat(5) @(negedge clk);
    pixel(80,340,24'h0B1624);
    pixel(80,351,24'hFFF0C2);
    pixel(80,366,24'h42E5AF);
    pixel(80,380,24'h37CFFF);
    pixel(93,380,24'h0B1624);
    pixel(63,380,24'h808080);pixel(576,380,24'h808080);
    visual_mode=1;
    pixel(80,352,24'h37DFFF);pixel(80,355,24'hE8F4FF);
    pixel(80,358,24'h37DFFF);pixel(80,350,24'h0B1624);
    visual_mode=0;
    for(i=0;i<100;i=i+1) begin
        for(j=3;j>0;j=j-1) expected[j]=expected[j-1];
        x_i=i[0] ? 93 : 80;y_i=380;
        expected[0]=i[0] ? 24'h0B1624 : 24'h37CFFF;
        @(negedge clk);
        if(i>=3 && rgb_out!==expected[3]) $fatal(1,"moving pixel pipeline misalignment at %d",i);
    end
    $display("PASS actual OSD spectrum gaps/peak/colors, wave channel colors, overlap, clipping and unchanged pixel pipeline");$finish;
end
endmodule
// Geometry test deliberately disables text pixels; production font remains
// independently generated and checked against its original glyph contents.
module saixian_font_rom(input clk,input [6:0] glyph_id,input [3:0] row,output reg [15:0] bits);
always @(posedge clk) bits<=0;
endmodule
