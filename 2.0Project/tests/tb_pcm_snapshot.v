`timescale 1ns/1ps
module tb_pcm_snapshot;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,sv=0;reg [7:0] sample=0;reg [5:0] idx=0;
wire [7:0] q;wire valid;
saixian_pcm_snapshot #(.DECIMATE(1)) dut(clk,rst,ft,sv,sample,idx,q,valid);
integer i;
task capture;input [7:0] offset;begin
 for(i=0;i<64;i=i+1) begin @(negedge clk);sv=1;sample=i+offset;end
 @(negedge clk);sv=0;
end endtask
task publish;begin ft=1;@(negedge clk);ft=0;repeat(2) @(negedge clk);end endtask
initial begin
 repeat(3) @(negedge clk);rst=0;capture(0);
 if(valid) $fatal(1,"snapshot published mid-frame");publish;
 for(i=0;i<64;i=i+1) begin idx=i;repeat(2) @(negedge clk);if(q!==i[7:0]) $fatal(1,"PCM mismatch");end
 capture(64);idx=4;repeat(2) @(negedge clk);
 if(q!==4) $fatal(1,"display bank overwritten before commit");publish;
 if(q!==68) $fatal(1,"new snapshot not published");
 $display("PASS real PCM capture, frame-atomic publication, bank isolation");$finish;
end
endmodule
