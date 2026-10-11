`timescale 1ns/1ps
module tb_audio_repair_integration;
reg clk=0,rst=1,tick=0,clear=0,enable=0,cue=0,active=1;
reg [23:0] bg_l=0,bg_r=0;
integer i,previous=0,before_previous=0;
integer queue[0:32],q;
always #5 clk=~clk;
top dut();
task sample;input integer value;input integer expected;
begin
    @(negedge clk);bg_l=24'(value*256);bg_r=24'(-value*256);
    tick=1;
    if($signed(dut.audio_left_data)!==24'(expected*256) ||
       $signed(dut.audio_right_data)!==24'(-expected*256))
        $fatal(1,"HDMI dry sample mismatch at %d got %d expected %d",i,$signed(dut.audio_left_data),expected*256);
    @(negedge clk);tick=0;repeat(330) @(negedge clk);
end endtask
initial begin
    force dut.video_clk=clk;force dut.rst_video=rst;
    force dut.cue_audio_valid=tick;force dut.bg_audio_left=bg_l;force dut.bg_audio_right=bg_r;
    force dut.audio_fifo_reset=clear;force dut.bgm_play_enable=1'b1;
    force dut.audio_repair_setting=enable;force dut.volume_setting=4'd6;
    force dut.cue_spectrum_active=cue;force dut.bg_audio_active=active;
    force dut.cue_audio_left=24'sd315904;force dut.cue_audio_right=-24'sd315904;
    force dut.frame_tick=1'b0;
    repeat(4) @(negedge clk);rst=0;repeat(4) @(negedge clk);
    for(q=0;q<33;q=q+1) queue[q]=0;
    for(i=0;i<300;i=i+1) begin
        sample((i*137)%16000,queue[0]);
        for(q=0;q<32;q=q+1) queue[q]=queue[q+1];
        queue[32]=(i*137)%16000;
    end
    // Restart an enabled track. An isolated PCM click must not reach HDMI.
    clear=1;enable=1;repeat(4) @(negedge clk);clear=0;
    repeat(5) sample(0,0);
    sample(30000,0);sample(0,0);sample(0,0);sample(0,0);
    repeat(80) sample(0,0);
    // Cue audio keeps its original path and stereo sign even with repair on.
    cue=1;active=0;repeat(4) @(negedge clk);tick=1;
    if(dut.audio_left_data!==24'sd315904 || dut.audio_right_data!==-24'sd315904)
        $fatal(1,"cue affected by TF repair");
    @(negedge clk);tick=0;
    clear=1;cue=0;repeat(4) @(negedge clk);
    if(dut.audio_left_data!==0 || dut.audio_right_data!==0) $fatal(1,"flush retained prior track PCM");
    $display("PASS real top: accepted HDMI PCM order/data, delayed player sample, click repair, cue bypass, volume and track flush");$finish;
end
endmodule
