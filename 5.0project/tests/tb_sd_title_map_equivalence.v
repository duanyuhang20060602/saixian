`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0,enabled=0,right=0;always #5 clk=~clk;
reg [3:0] effect=0;reg [8:0] progress=0;reg [9:0] x=0,y=0,wx=0,wy=0;
wire ov,bv;wire [9:0] a,b,c,ox,oy,ba,bb,bc,bx,by;
wire [8:0] alpha,b_alpha;wire [4:0] shade,b_shade;wire [2:0] shine,b_shine;
water_effect_map dut(clk,rst,valid,enabled,right,effect,progress,x,y,wx,wy,ov,a,b,c,ox,oy,alpha,shade,shine);
water_effect_map_before old(clk,rst,valid,enabled,right,effect,progress,x,y,wx,wy,bv,ba,bb,bc,bx,by,b_alpha,b_shade,b_shine);
integer f,p,d,e,k,submitted=0,checked=0;
always @(posedge clk)begin #1;
 if(!rst)begin
  if(ov!==bv)$fatal(1,"effect valid latency changed");
  if(ov)begin
   if({a,b,c,ox,oy,alpha,shade,shine}!=={ba,bb,bc,bx,by,b_alpha,b_shade,b_shine})
    $fatal(1,"effect output changed at sample %0d",checked);
   checked=checked+1;
  end
 end
end
initial begin
 repeat(8)@(negedge clk);rst=0;repeat(8)@(negedge clk);
 for(f=0;f<11;f=f+1)for(p=0;p<=256;p=p+1)for(d=0;d<2;d=d+1)for(e=0;e<2;e=e+1)for(k=0;k<8;k=k+1)begin
  effect=f;progress=p;right=d;enabled=e;valid=1;
  case(k)
   0:begin x=0;y=0;end
   1:begin x=639;y=719;end
   2:begin x=320;y=360;end
   3:begin x=319;y=359;end
   default:begin x=(p*7+f*31+k*97)%640;y=(p*11+f*57+k*41)%720;end
  endcase
  wx=(x+13)%640;wy=(y+17)%720;submitted=submitted+1;
  @(negedge clk);valid=0;@(negedge clk);
  if(k==7)repeat(2)@(negedge clk);
 end
 repeat(15)@(negedge clk);
 if(checked!=submitted)$fatal(1,"effect output count changed %0d/%0d",checked,submitted);
 $display("PASS endpoint decode moved before geometry: %0d exact outputs, all 11 effects, every progress value, both directions, enabled/disabled, borders and bubbles; unchanged latency",checked);$finish;
end
initial begin #3000000;$fatal(1,"map equivalence timeout");end
endmodule
