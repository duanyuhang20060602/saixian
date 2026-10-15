`timescale 1ns/1ps
module tb_audio_osd_port;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,wm=0,de=1;reg [9:0] x=100;reg [8:0] y=350;
reg [6:0] h=50,p=55;reg [31:0] wave=32'h18200000;wire [23:0] rgb;
saixian_osd_overlay dut(.clk(clk),.rst(rst),.frame_tick(ft),.de_i(de),.x_i(x),.y_i(y),.rgb_in_i(24'h123456),
 .display_valid(1'b1),.error_code(3'd0),.state(4'd0),.settings_mode(1'b0),
 .waveform_mode(wm),.visual_height(h),.visual_peak(p),.visual_wave(wave),.visual_fft_valid(1'b1),.visual_wave_valid(1'b1),
 .font_ready(1'b0),.font_bits(16'd0),.ticker_x(11'd0),.ticker_text_length(5'd0),.title_text_length(5'd0),.rgb_out(rgb));
task check;
 input [23:0] expected;
 begin repeat(8)@(negedge clk);if(rgb!==expected)$fatal(1,"OSD pixel got %h expected %h",rgb,expected);end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;check(24'h42e5af);
 y=336;check(24'hfff0c2);
 h=0;p=0;y=350;check(24'h0d2740);
 wm=1;ft=1;@(negedge clk);ft=0;
 y=350;check(24'h37dfff);
 wave=32'h00001820;check(24'hffb85c);
 wave=32'h18201820;check(24'he8f4ff);
 x=600;y=300;check(24'h123456);
 de=0;check(24'h000000);
 $display("PASS OSD real spectrum, peak, silence, L/R/overlap waveform and bypass");$finish;
end
endmodule
