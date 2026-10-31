`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,we=0;reg [5:0] wi=0;reg [31:0] wd=0;
reg view=1;reg [11:0] x=0;reg [5:0] y=0;
wire custom,ink;wire [1:0] alpha;
photo_rank_text dut(.clk(clk),.rst(rst),.frame_tick(tick),.word_valid(we),.word_row(3'd0),.word_index(wi),.word_data(wd),
 .word_length(4'd8),.word_score(16'h1234),.read_valid(1'b1),.rank_view(view),.read_row(3'd0),.read_x(x),.read_y(y),
 .name_y_valid(1'b1),.digit_y_valid(1'b0),.custom(custom),.ink(ink),.alpha(alpha));
function [15:0] pattern;input integer c,r;begin pattern=(16'h8101 ^ (16'h5317*(c+1))) ^ (16'h2345*r);end endfunction
integer i,j,k,c,r,col,start,checked=0;reg expected;reg [15:0] reference;
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<64;i=i+1)begin
  wi=i;wd={pattern(i/8,(i%8)*2),pattern(i/8,(i%8)*2+1)};we=1;
  @(negedge clk);we=0;repeat(2)@(negedge clk);
 end
 tick=1;@(negedge clk);tick=0;repeat(3)@(negedge clk);
 for(k=0;k<2;k=k+1)begin
  view=k==0;start=view ? 268:528;
  for(j=0;j<64;j=j+1)for(i=0;i<256;i=i+1)begin
   x=start+i;y=j;
   c=i/24;r=((j-2)*2)/3;col=((i%24)*2)/3;
   reference=pattern(c,r);expected=i<192 && j>=2 && j<26 && reference[15-col];
   @(posedge clk);#1;
   if(custom!==1 || ink!==expected || alpha!==(expected ? 2'd3:2'd0))
    $fatal(1,"24px name resampling mismatch view=%0d x=%0d y=%0d alpha=%0d expected=%0d",view,i,j,alpha,expected);
   checked=checked+1;@(negedge clk);
  end
 end
 $display("PASS %0d independently mapped pixels: eight names, all 16 source rows/columns, 24x24 size, rank/podium, clipping and latency",checked);$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
