`timescale 1ns/1ps
module tb_mapper_equivalence;
reg [10:0] x,y_offset;reg [9:0] y;reg [20:0] old_base,new_base;
reg enabled,right;reg [2:0] effect;wire [20:0] got,want;
saixian_frame_mapper dut(x,y,old_base,new_base,enabled,right,effect,y_offset,got);
baseline_frame_mapper reference(x,y,old_base,new_base,enabled,right,effect,y_offset,want);
integer i,j,k,e,r,seed=20261010,checks=0;
initial begin
 for(e=0;e<6;e=e+1)for(r=0;r<2;r=r+1)for(k=0;k<=640;k=k+17)
 for(j=0;j<720;j=j+29)for(i=0;i<640;i=i+17)begin
  x=i;y=j;y_offset=k;enabled=1;right=r;effect=e;
  old_base=$random(seed);new_base=$random(seed);#1;
  if(got!==want)$fatal(1,"mapper changed effect=%d right=%d offset=%d x=%d y=%d",e,r,k,i,j);
  checks=checks+1;
 end
 for(i=0;i<5000;i=i+1)begin
  x=$random(seed);y=$random(seed);y_offset=$random(seed);enabled=$random(seed);right=$random(seed);effect=$random(seed);
  old_base=$random(seed);new_base=$random(seed);#1;if(got!==want)$fatal(1,"mapper randomized mismatch");checks=checks+1;
 end
 $display("PASS carry-select mapper matches 20261008 reference: %0d states, six effects, directions, row/carry boundaries",checks);$finish;
end
endmodule
