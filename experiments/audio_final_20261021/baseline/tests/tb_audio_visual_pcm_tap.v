`timescale 1ns/1ps
// Check the integration tap against the exact bus accepted by HDMI, then
// check that the registered sample-valid writes that same stereo word.
module tb_audio_visual_pcm_tap;
reg clk=0,rst=1,accepted=0;
reg [23:0] pcm_l=0,pcm_r=0;
reg previous_valid=0;
reg [31:0] previous_word;
integer i,count=0;
always #5 clk=~clk;
top dut(.clk(clk),.key(4'hf),.sw(2'd0),.hdmi_hpd(1'b1),.sd_miso(1'b1),.hmi_uart_rx(1'b1));
initial begin
    force dut.video_clk=clk;force dut.rst_video=rst;
    force dut.audio_valid=accepted;force dut.audio_left_data=pcm_l;force dut.audio_right_data=pcm_r;
    force dut.frame_tick=1'b0;
    repeat(4) @(negedge clk);rst=0;
    for(i=0;i<200;i=i+1) begin
        accepted=i%3!=0;pcm_l=24'hfedcba+i*7919;pcm_r=24'h123456-i*3571;
        @(posedge clk);#1;
        if(dut.visual_sample_valid!==accepted) $fatal(1,"HDMI sample valid misaligned");
        if(accepted && {dut.visual_right,dut.visual_left}!=={pcm_r[23:8],pcm_l[23:8]})
            $fatal(1,"tap differs from HDMI accepted stereo bus");
        if(previous_valid) begin
            if(dut.u_visual_fft.capture_ram.banks[0].mem[count]!==previous_word)
                $fatal(1,"FFT sample-valid paired with the wrong PCM word %d",count);
            count=count+1;
        end
        if(dut.u_visual_fft.capture_index!==count) $fatal(1,"tap duplicated or dropped a valid sample");
        previous_valid=accepted;previous_word={pcm_r[23:8],pcm_l[23:8]};
        @(negedge clk);
    end
    $display("PASS actual top HDMI PCM tap: stereo data/valid alignment and %d accepted FFT writes",count);$finish;
end
endmodule
