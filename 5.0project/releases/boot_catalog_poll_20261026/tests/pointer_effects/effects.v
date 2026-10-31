`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,iv=0;always #5 clk=~clk;
reg[3:0] fx;reg[8:0] p;reg[10:0] cx;reg[9:0] cy,x,y;
wire ov;wire[9:0] a,b,c,ox,oy;wire[8:0] alpha;wire[4:0] shade;wire[2:0] shine;
water_effect_map #(.POINTER_CENTER(1)) d(.clk(clk),.rst(rst),.valid(iv),.enabled(1'b1),.right(1'b0),.effect(fx),
 .progress(p),.ox(x),.oy(y),.wx(x),.wy(y),.out_valid(ov),.old_x(a),.old_y(b),.new_x(c),.out_x(ox),.out_y(oy),
 .alpha(alpha),.shade(shade),.shine(shine),.center_x(cx),.center_y(cy));
integer fd,n,ea,eb,ec,eq,es,eh,cycles,count=0;
initial begin
 repeat(5)@(negedge clk);rst=0;fd=$fopen("vectors.txt","r");
 while(!$feof(fd))begin
  n=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d",fx,p,cx,cy,x,y,ea,eb,ec,eq,es,eh);
  if(n==12)begin
   repeat(15)@(negedge clk);iv=1;@(negedge clk);iv=0;cycles=0;
   while(!ov && cycles<20)begin @(negedge clk);cycles=cycles+1;end
   if(!ov || {a,b,c,alpha,shade,shine}!=={ea[9:0],eb[9:0],ec[9:0],eq[8:0],es[4:0],eh[2:0]} || ox!==x || oy!==y)
    $fatal(1,"pointer map case %d fx%0d p%0d center %0d,%0d xy %0d,%0d got %0d %0d %0d %0d %0d %0d expected %0d %0d %0d %0d %0d %0d",count,fx,p,cx,cy,x,y,a,b,c,alpha,shade,shine,ea,eb,ec,eq,es,eh);
   count=count+1;repeat(2)@(negedge clk);
  end
 end
 $display("PASS pointer-centred map cases=%0d: corner origins, signed range, both effects, near-end coverage and exact endpoints",count);$finish;
end
endmodule
