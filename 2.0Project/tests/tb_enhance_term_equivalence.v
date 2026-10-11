`timescale 1ns/1ps
module tb_enhance_term_equivalence;
reg clk=0;always #5 clk=~clk;
reg signed [9:0] sample;
reg [1:0] strength=0;
saixian_adaptive_enhance #(.WIDTH(2),.PHOTO_SMOOTH(0)) d0(.clk(clk),.rst(1'b1),.de(1'b0),.strength(strength));
saixian_adaptive_enhance #(.WIDTH(2),.PHOTO_SMOOTH(1)) d1(.clk(clk),.rst(1'b1),.de(1'b0),.strength(strength));
baseline_enhance #(.WIDTH(2),.PHOTO_SMOOTH(0)) b0(.clk(clk),.rst(1'b1),.de(1'b0),.strength(strength));
baseline_enhance #(.WIDTH(2),.PHOTO_SMOOTH(1)) b1(.clk(clk),.rst(1'b1),.de(1'b0),.strength(strength));
integer x,s,checks=0;
initial begin
 force d0.detail=sample;force d1.detail=sample;force b0.detail=sample;force b1.detail=sample;
 // Both source luma and the convex neighborhood mean are unsigned 8-bit:
 // every feasible residual is in [-255,255]. Exhaust the entire domain.
 for(s=0;s<4;s=s+1)begin strength=s;
  for(x=-255;x<=255;x=x+1)begin sample=x;#1;
   if(d0.detail_term!==b0.detail_term || d1.detail_term!==b1.detail_term)
    $fatal(1,"detail mismatch d=%d strength=%d got=%d/%d expected=%d/%d",x,s,d0.detail_term,d1.detail_term,b0.detail_term,b1.detail_term);
   checks=checks+2;
  end
 end
 $display("PASS bounded enhancement equals prior RTL: %0d comparisons, every feasible residual, all strengths, photo smoothing on/off",checks);$finish;
end
endmodule
