`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
water_drop_vector square_unit(.clk(1'b0),.rst(1'b1));
water_effect_map effects_unit(.clk(1'b0),.rst(1'b1));
water_blend blend_unit(.clk(1'b0),.rst(1'b1));
water_edge edge_unit(.clk(1'b0),.rst(1'b1));
reg rst=1,valid=0;reg[23:0] rad;reg[15:0] tag;wire ov;wire[11:0] root;wire[15:0] ot;
water_sqrt #(.DW(16)) sqrt_unit(clk,rst,valid,rad,tag,ov,root,ot);
reg[7:0] sine_reference[0:63];
integer i,j,k,checks=0,sqrt_checks=0;
reg[11:0] expected[0:65535];reg[31:0] random_state=32'h71a0b43d;
function[11:0] reference_sqrt;input[23:0] n;integer b;reg[23:0] trial;reg[11:0] q;begin
 q=0;for(b=11;b>=0;b=b-1)begin trial=q|(1<<b);if(trial*trial<=n)q=trial;end
 reference_sqrt=q;end endfunction
always @(posedge clk)begin
 #1;if(ov)begin if(root!==expected[ot])$fatal(1,"sqrt rad tag=%d got=%d expected=%d",ot,root,expected[ot]);sqrt_checks=sqrt_checks+1;end
end
initial begin
 $readmemh("water_fx_wave.hex",sine_reference);
 for(i=0;i<64;i=i+1)begin
  if($signed(effects_unit.extra.wave_value(i))!=$signed(sine_reference[i]))$fatal(1,"folded wave phase %d",i);
  checks=checks+1;
 end
 for(i=-2047;i<=2047;i=i+1)begin
  if(square_unit.exact_square(i)!==i*i)$fatal(1,"square %d",i);checks=checks+1;
 end
 for(i=-64;i<=63;i=i+1)for(j=0;j<=256;j=j+1)begin
  if($signed(blend_unit.alpha_product(i,j))!=i*j)$fatal(1,"alpha %d %d",i,j);checks=checks+1;
 end
 for(i=-64;i<=63;i=i+1)for(j=0;j<256;j=j+1)begin
  if($signed(effects_unit.extra.small_product(i,j))!=i*j)$fatal(1,"wave %d %d",i,j);checks=checks+1;
 end
 for(i=-256;i<=255;i=i+1)for(j=0;j<256;j=j+1)begin
  if($signed(edge_unit.edge_product(i,j))!=(((i*j+32768)&65535)-32768))$fatal(1,"edge %d %d",i,j);checks=checks+1;
 end
 repeat(3)@(negedge clk);rst=0;
 for(i=0;i<50000;i=i+1)begin
  @(negedge clk);
  random_state=(random_state*1664525)+1013904223;
  if(i<12288)begin k=i/3;rad=k*k;if(i%3==0&&k>0)rad=rad-1;else if(i%3==2)rad=rad+1;end
  else rad=random_state[23:0];
  tag=i;valid=i%17!=16;expected[tag]=reference_sqrt(rad);
 end
 @(negedge clk);valid=0;repeat(15)@(negedge clk);
 if(sqrt_checks!=47059)$fatal(1,"sqrt missing outputs %d",sqrt_checks);
 $display("PASS arithmetic %0d exhaustive products/squares and %0d pipelined sqrt boundary/random vectors",checks,sqrt_checks);$finish;
end
endmodule

