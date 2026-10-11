`timescale 1ns/1ps
module tb_repair_equivalence;
reg clk=0,rst=1,clear=0,valid=0,en=0;
reg signed [15:0] li=0,ri=0;
wire signed [15:0] lo,ro,bl,br;
wire ov,bv;
integer i,k;
always #5 clk=~clk;
saixian_audio_repair dut(clk,rst,clear,valid,en,li,ri,lo,ro,ov);
baseline_audio_repair baseline(clk,rst,clear,valid,en,li,ri,bl,br,bv);
initial begin
repeat(3)@(negedge clk);rst=0;
for(i=0;i<10000;i=i+1)begin
 @(negedge clk);valid=1;
 li=$random;ri=$random;
 if(i%333==0)en=~en;
 @(negedge clk);valid=0;
 repeat(318)@(negedge clk);
 if(lo!==bl || ro!==br)$fatal(1,"V4 mismatch sample %d got %d/%d reference %d/%d",i,lo,ro,bl,br);
 if(i%997==0)begin clear=1;repeat(4)@(negedge clk);clear=0;end
end
// Clearing in the middle of FIR processing discards both channel histories.
valid=1;@(negedge clk);valid=0;repeat(50)@(negedge clk);
clear=1;repeat(3)@(negedge clk);clear=0;repeat(330)@(negedge clk);
if(lo!==0 || ro!==0 || bl!==0 || br!==0)$fatal(1,"mid-operation clear");
$display("PASS shared audio arithmetic equals morning V4: 10000 random stereo samples, crossfade, track clear, mid-operation clear");$finish;
end
endmodule
