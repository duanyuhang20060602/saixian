`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,valid=0,cm=0;reg[31:0] rgb=0;reg[4:0] shade=0;reg[2:0] shine=0;
wire ov;wire[31:0] lit;wire[31:0] scalar;
water_surface_light dut(clk,rst,valid,rgb,shade,shine,ov,lit,cm);
water_color_light combinational(rgb,shade,shine,scalar,cm);
integer f,z,n,count=0;reg[31:0] expected;
reg iv=0,last=0;reg[2:0] amount=0;reg[31:0] source=0;wire fv,fl;wire[31:0] result;
water_color_fringe fringe(clk,rst,1'b1,iv,last,amount,source,fv,fl,result);
integer ef,row,pair,got=0;reg[31:0] wanted;
always @(posedge clk)begin #1;
 if(fv)begin
  z=$fscanf(ef,"%h",wanted);
  if(z!=1||result!==wanted||fl!==(got%320==319))$fatal(1,"fringe mismatch word%0d got%h want%h last%b",got,result,wanted,fl);
  got=got+1;
 end
end
initial begin
 f=$fopen("color_light_vectors.txt","r");ef=$fopen("color_fringe_expected.txt","r");
 repeat(4)@(negedge clk);rst=0;
 while(!$feof(f))begin
  z=$fscanf(f,"%d %h %d %d %h",cm,rgb,shade,shine,expected);
  if(z==5)begin
   valid=1;#1;if(scalar!=={expected[31:16],expected[31:16]})$fatal(1,"scalar light %0d got%h want%h",count,scalar,expected);
   @(negedge clk);valid=0;
   @(posedge clk);#2;if(!ov||lit!==expected)$fatal(1,"color light transaction%0d got%h want%h",count,lit,expected);
   @(negedge clk);count=count+1;
  end
 end
 f=$fopen("color_fringe_input.txt","r");
 for(row=0;row<12;row=row+1)begin
  for(pair=0;pair<320;pair=pair+1)begin
   z=$fscanf(f,"%h %d",source,amount);iv=1;last=pair==319;
   @(negedge clk);iv=0;last=0;@(negedge clk);
   if(pair%17==0)repeat(pair%5)@(negedge clk);
  end
  repeat(24)@(negedge clk);
  if(got!=(row+1)*320)$fatal(1,"fringe row did not drain");
 end
 $display("PASS color_surface %0d shared-DSP light cases; %0d spatial RGB pairs, all shifts, borders, input stalls, row flush",count,got);$finish;
end
initial begin #100000000;$fatal(1,"color surface timeout");end
endmodule
