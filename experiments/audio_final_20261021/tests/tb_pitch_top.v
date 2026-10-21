`timescale 1ns/1ps
module tb_pitch_top;
reg clk=0,rst=1,tick=0,repair_valid=0,short_press=0,long_press=0;
reg signed [15:0] input_l=4096,input_r=-8192;
integer n,j,outputs=0,cycles=0,last_tick=0;
always #5 clk=~clk;
top dut(.clk(clk),.key(4'hf),.sw(2'd0),.hdmi_hpd(1'b1),.sd_miso(1'b1),.hmi_uart_rx(1'b1));
always @(posedge clk) cycles=cycles+1;
always @(negedge clk)if(dut.pitch_valid)begin
    outputs=outputs+1;
    if(cycles-last_tick>=1562)$fatal(1,"pitch missed HDMI acceptance deadline");
    if(dut.pitch_overrun)$fatal(1,"pitch overrun at top");
end
initial begin
    force dut.video_clk=clk;force dut.rst_video=rst;
    force dut.audio_fifo_reset=1'b0;force dut.bgm_play_enable=1'b1;
    force dut.repair_out_valid=repair_valid;
    force dut.repaired_bg_left={input_l,8'd0};force dut.repaired_bg_right={input_r,8'd0};
    force dut.cue_audio_valid=tick;force dut.cue_spectrum_active=1'b0;
    force dut.key2_result_short_press=short_press;force dut.key2_result_long_press=long_press;
    force dut.carousel_mode=1'b1;force dut.settings_mode=1'b0;
    force dut.frame_tick=1'b0;
    $display("BEGIN pitch top integration");$fflush();
    repeat(5)@(negedge clk);rst=0;
    if(dut.volume_setting!==4'd5)$fatal(1,"default volume must remain 5");
    for(n=1;n<=5;n=n+1)begin
        short_press=1;@(negedge clk);short_press=0;
        if(dut.pitch_mode!==(n==5 ? 3'd0 : n[2:0]))$fatal(1,"KEY2 mode cycle");
        @(negedge clk);
    end
    short_press=1;@(negedge clk);short_press=0;
    long_press=1;@(negedge clk);long_press=0;
    if(dut.pitch_mode!=0)$fatal(1,"long press did not restore dry");
    for(n=0;n<24;n=n+1)begin
        tick=1;last_tick=cycles;
        @(posedge clk);#1;
        if(dut.audio_valid!==1'b1)$fatal(1,"HDMI audio tick was modified");
        @(negedge clk);tick=0;
        repeat(299)@(negedge clk);repair_valid=1;
        @(negedge clk);repair_valid=0;
        repeat(1261)@(negedge clk);
    end
    if(outputs!=24 || dut.pitch_overrun)$fatal(1,"pitch output count or overrun");
    // The standalone integer test covers the complete warm-up and dry delay.
    // At this boundary inject known effect output to independently check mixer,
    // volume and the HDMI/FFT tap, without simulating thousands of video scans.
    force dut.pitched_left=16'sd4096;force dut.pitched_right=-16'sd8192;
    repeat(8)@(negedge clk);tick=1;
    @(posedge clk);#1;
    if(dut.audio_left_data!==24'sd1310720 || $signed(dut.audio_right_data)!==-24'sd2621440)
        $fatal(1,"effect boundary -> volume PCM wrong");
    if(!dut.visual_sample_valid || dut.visual_left!==16'sd5120 || dut.visual_right!==-16'sd10240)
        $fatal(1,"FFT tap did not follow processed HDMI PCM");
    // Reset defaults through the real settings controller as well.
    force dut.hmi_setting_valid=1'b1;force dut.hmi_setting_id=3'd4;force dut.hmi_setting_value=8'd0;
    repeat(2)@(negedge clk);
    if(dut.volume_setting!==0)$fatal(1,"volume mute setting failed");
    force dut.hmi_setting_valid=1'b0;force dut.hmi_reset_defaults=1'b1;
    @(negedge clk);
    if(dut.volume_setting!==5)$fatal(1,"reset defaults did not restore volume 5");
    $display("PASS actual top: KEY2 modes/reset, 24 real pitch transactions meet HDMI deadline; injected effect output reaches volume and FFT tap");$finish;
end
endmodule
