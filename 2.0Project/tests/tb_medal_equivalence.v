`timescale 1ns/1ps
module tb_medal_equivalence;
reg clk=0,rst=1;
reg [10:0] x;
reg [9:0] y;
reg [11:0] displacement;
integer i,j,v,dx,dy,radius;
always #5 clk=~clk;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.trigger(1'b0),.select_blue(1'b0),
 .select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),.sprint_background_valid(1'b0),
 .x_in(11'd0),.y_in(10'd0),.de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0));
initial begin
force dut.raster_x=x;force dut.raster_y=y;force dut.row_shift=displacement;
force dut.pre_podium=1'b1;force dut.pre_row_id=4'd0;
repeat(3)@(negedge clk);rst=0;
for(j=0;j<8;j=j+1)for(i=0;i<2048;i=i+1)begin
 @(negedge clk);x=i;y=$random;
 case(j)0:displacement=0;1:displacement=1;2:displacement=127;3:displacement=128;
 4:displacement=1200;5:displacement=1400;6:displacement=1600;7:displacement=4095;endcase
 v=(i+displacement)&4095;dx=v>=270 ? v-270 : 270-v;dy=y>=228 ? y-228 : 228-y;
 radius=(dx&31)+(dy&31);
 @(posedge clk);#1;
 if(dut.medal_dx!==12'(dx))$fatal(1,"medal center/absolute distance differs x=%d shift=%d",i,displacement);
 if(dut.medal_outer!==(dx<=31 && dy<=31 && radius<=44) ||
    dut.medal_inner!==(dx<=24 && dy<=24 && radius<=34) ||
    dut.medal_star!==(dx<=24 && dy<=24 && radius<=13))$fatal(1,"medal pixel differs");
end
$display("PASS medal timing split: 16384 positions, center/absolute distance, wrap, rims/star pixels and original stage latency");$finish;
end
endmodule
