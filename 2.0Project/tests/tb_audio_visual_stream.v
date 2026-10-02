`timescale 1ns/1ps
module tb_audio_visual_stream;
reg clk=0,rst=1,frame_tick=0,sample_valid=0;
reg signed [15:0] left=0,right=0;
reg [4:0] read_band=3;
wire [6:0] read_height,read_peak;
wire valid,block_done;
integer cycles=0,samples=0,blocks=0;
reg last_frame=0,last_bank=0;
reg [6:0] held_height,held_peak;
always #5 clk=~clk;
saixian_av_fft dut(.*);
always @(negedge clk) begin
    if(!rst) begin
        cycles=cycles+1;frame_tick=(cycles%4096)==0;
        sample_valid=(cycles%32)==0;
        if(sample_valid) begin
            samples=samples+1;
            left=(samples%128<64) ? 16'sd20000 : -16'sd20000;
            right=-left;
        end
        if(block_done) blocks=blocks+1;
        if(dut.display_bank!=last_bank && !last_frame) $fatal(1,"snapshot bank changed away from frame");
        last_frame=frame_tick;last_bank=dut.display_bank;
        // Allow the RAM's one-cycle read when the display bank flips.
        if(cycles%4096>4 && valid) begin
            if(read_height!==held_height || read_peak!==held_peak) $fatal(1,"frame torn under overload");
        end
        held_height=read_height;held_peak=read_peak;
        if(cycles==700000) begin
            if(blocks<3) $fatal(1,"analyzer starved under continuous input");
            $display("PASS continuous stereo overload: %d samples, %d complete FFTs, no overwrite/deadlock or mid-frame publication",samples,blocks);$finish;
        end
    end
end
initial begin repeat(4) @(negedge clk);rst=0;end
endmodule
