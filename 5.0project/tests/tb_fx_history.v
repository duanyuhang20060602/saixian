`timescale 1ns/1ps
module tb_fx_history;
reg clk=0;always #5 clk=~clk;
reg we=0;reg [5:0] wa=0,ra=0;reg [63:0] wd=0;
wire [63:0] packed_q,original_q;integer i;
saixian_repair_history_ram #(.PACKED(1)) packed_ram(clk,we,wa,ra,wd,packed_q);
saixian_repair_history_ram #(.PACKED(0)) original_ram(clk,we,wa,ra,wd,original_q);
initial begin
 for(i=0;i<64;i=i+1)begin @(negedge clk);wa=i;wd={$random,$random};we=1;end
 @(negedge clk);we=0;repeat(2)@(negedge clk);
 for(i=0;i<5000;i=i+1)begin
  @(negedge clk);wa=$random;ra=$random;wd={$random,$random};we=$random;
  @(posedge clk);#2;
  if(packed_q!==original_q)$fatal(1,"history lane/latency/collision mismatch %0d",i);
 end
 $display("PASS packed history with unmodified vendor RAM model: 5000 random 64-bit reads/writes, lanes, latency and collisions equal original four lanes");$finish;
end
endmodule
