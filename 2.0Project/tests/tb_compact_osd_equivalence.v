`timescale 1ns/1ps
module tb_compact_osd_equivalence;
reg clk=0,rst=1,de_i=0;
reg [9:0] x_i=0;
reg [8:0] y_i=0;
reg [23:0] rgb_in_i=0;
reg visual_mode=0,settings_mode=0,display_valid=1;
reg [3:0] state=0;
reg [2:0] error_code=0;
reg [6:0] visual_height=0,visual_peak=0;
wire [23:0] rgb_out,reference_out;
reg [31:0] random_word=32'h3538ab27;
integer i;
always #5 clk=~clk;
`define OSD_PORTS(OUTPUT) \
    .clk(clk),.rst(rst),.frame_tick(1'b0),.de_i(de_i),.x_i(x_i),.y_i(y_i),.rgb_in_i(rgb_in_i), \
    .display_valid(display_valid),.loading_phase(3'd0),.state(state),.project_id(2'd0),.minutes(7'd23),.seconds(6'd31), \
    .countdown_value(4'd2),.ticker_x(10'd91),.source_width_bcd(16'h1280),.source_height_bcd(16'h0720), \
    .error_code(error_code),.transition_active(1'b0),.transition_level(6'd0),.audio_level(8'd0), \
    .spectrum_active(1'b0),.spectrum_tone_bin(5'd0),.settings_mode(settings_mode),.setting_item(3'd2), \
    .volume_setting(4'd5),.brightness_setting(4'd4),.contrast_setting(4'd4),.sharpness_setting(2'd1), \
    .saturation_setting(4'd4),.invert_setting(1'b0),.vintage_setting(1'b0),.enhancement_setting(2'd1), \
    .audio_sample_valid(1'b0),.audio_sample(8'd0),.visual_mode(visual_mode),.visual_height(visual_height), \
    .visual_peak(visual_peak),.visual_wave(32'hf810fc08),.visual_fft_valid(1'b1),.visual_wave_valid(1'b1),.rgb_out(OUTPUT)
saixian_osd_overlay dut(`OSD_PORTS(rgb_out));
saixian_osd_overlay_ref ref_dut(`OSD_PORTS(reference_out));
`undef OSD_PORTS
initial begin
    repeat(5) @(negedge clk);rst=0;
    for(i=0;i<100000;i=i+1) begin
        random_word={random_word[30:0],random_word[31]^random_word[21]^random_word[1]^random_word[0]};
        x_i=random_word[9:0];y_i=random_word[18:10];rgb_in_i=random_word[23:0];de_i=i%19<17;
        state=(i/997)%9;settings_mode=(i/331)%7==0;error_code=(i/199)%11==0 ? 3'd2 : 0;
        display_valid=(i/257)%13!=0;visual_mode=random_word[24];
        visual_height=random_word[6:0]%73;visual_peak=random_word[13:7]%73;
        @(negedge clk);
        if(rgb_out!==reference_out) $fatal(1,"OSD priority/latency differs at cycle %d got=%h expected=%h",i,rgb_out,reference_out);
    end
    $display("PASS 100000 OSD pixel comparisons against accepted RTL: FFT/wave, text, all pages, settings, errors and DE");$finish;
end
endmodule
// Both instances use the same deterministic synchronous font model so the
// comparison also checks text priority and glyph/column pipeline alignment.
module saixian_font_rom(input clk,input [6:0] glyph_id,input [3:0] row,output reg [15:0] bits);
always @(posedge clk) bits<=(16'h8151 >> row) ^ (glyph_id << 3);
endmodule
