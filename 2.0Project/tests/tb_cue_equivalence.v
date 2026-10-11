`timescale 1ns/1ps
module tb_cue_equivalence;
reg clk=0;always #5 clk=~clk;reg rst=1;reg [3:0] cue=0;
wire valid_a,valid_b,busy_a,busy_b,active_a,active_b;
wire [23:0] left_a,right_a,left_b,right_b;wire [7:0] level_a,level_b;wire [4:0] bin_a,bin_b;
saixian_audio_cue #(.CLK_FREQ_HZ(96000),.SAMPLE_RATE_HZ(48000)) dut(clk,rst,cue,valid_a,left_a,right_a,level_a,busy_a,active_a,bin_a);
baseline_audio_cue #(.CLK_FREQ_HZ(96000),.SAMPLE_RATE_HZ(48000)) reference(clk,rst,cue,valid_b,left_b,right_b,level_b,busy_b,active_b,bin_b);
integer i;
always @(posedge clk)begin
 #1;if({valid_a,left_a,right_a,level_a,busy_a,active_a,bin_a}!=={valid_b,left_b,right_b,level_b,busy_b,active_b,bin_b})
 $fatal(1,"cue threshold optimization changed audio or cue metadata");
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<250000;i=i+1)begin
  @(negedge clk);cue=0;
  case(i)0:cue=1;20000:cue=2;50000:cue=3;100000:cue=4;150000:cue=5;endcase
 end
 $display("PASS cue threshold is sample-exact against 20261008 reference: five cues, tone/silence segments, 250000 cycles");$finish;
end
endmodule
