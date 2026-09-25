`timescale 1ns/1ps
module tb_victory_slice;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,tr=0;reg [10:0] x=0;reg [9:0] y=0;
wire busy,de,vs;wire [23:0] rgb;
saixian_battle_result_fx dut(clk,rst,ft,tr,x,y,1'b1,1'b0,24'd0,busy,de,vs,rgb);
task tick;begin @(negedge clk);ft=1;@(negedge clk);ft=0;end endtask
integer i,j,f;
initial begin
repeat(3) @(negedge clk);rst=0;tr=1;tick;tr=0;
repeat(103) tick;
if(dut.slice_a==0 && dut.slice_b==0 && dut.slice_c==0)$fatal(1,"no slice displacement");
`ifdef EXPORT_FRAME
f=$fopen("doc/hmi_ui/blue_victory_slice_entry.ppm","wb");
$fwrite(f,"P6\n1280 720\n255\n");
for(j=0;j<720;j=j+1)for(i=0;i<1280;i=i+1)begin
@(negedge clk);x=i;y=j;repeat(4)begin @(posedge clk);#1;end
$fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);
end
$fclose(f);
`endif
repeat(30)tick;
if(dut.slice_a!=0 || dut.slice_b!=0 || dut.slice_c!=0)$fatal(1,"slices do not settle");
$display("PASS staggered displacement and settled offsets");$finish;
end
endmodule
