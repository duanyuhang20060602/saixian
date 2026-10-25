`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #10 clk=~clk;
reg [31:0] material=0;reg signed [5:0] lx=0,ly=0;reg wall=0;reg [6:0] level=0;wire [23:0] rgb;
reg [43:0] inputs[0:36863];reg [23:0] expected[0:36863];reg [23:0] walls[0:127];integer i;
photo_relief_shade_kernel dut(.clk(clk),.rst(rst),.material(material),.light_x(lx),.light_y(ly),.wall(wall),.wall_level(level),.rgb(rgb));
initial begin
 $readmemh("kernel_inputs.hex",inputs);$readmemh("kernel_expected.hex",expected);$readmemh("wall_table.hex",walls);
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<36864;i=i+1)begin
  {lx,ly,material}=inputs[i];repeat(13)@(negedge clk);
  if(rgb!==expected[i])$fatal(1,"kernel %0d material=%h light=%0d,%0d actual=%h expected=%h",i,material,lx,ly,rgb,expected[i]);
 end
 wall=1;for(i=0;i<128;i=i+1)begin level=i;repeat(13)@(negedge clk);if(rgb!==walls[i])$fatal(1,"wall %0d %h/%h",i,rgb,walls[i]);end
 $display("PASS all 24x256 actual material entries at six light positions/extremes; 128 exact wall colors; no precision loss");$finish;
end
initial begin #20000000;$fatal(1,"kernel timeout");end
endmodule
