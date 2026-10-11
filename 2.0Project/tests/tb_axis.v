`timescale 1ns/1ps
module tb_axis;
reg clk=0;always #5 clk=~clk;
reg rst=1,vs=0,de=0;reg [23:0] rgb=0;
wire user,valid,last;wire [23:0] data;
video_rgb_to_axis_640x480 #(.H_ACTIVE(1280)) dut(clk,rst,vs,de,rgb,user,valid,last,data);
integer frame,row,col,users=0,lasts=0;
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(frame=0;frame<2;frame=frame+1)begin
  vs=1;repeat(5)@(negedge clk);vs=0;repeat(5)@(negedge clk);
  for(row=0;row<3;row=row+1)begin
   for(col=0;col<1280;col=col+1)begin
    de=1;rgb=(frame<<20)+(row<<12)+col;
    @(posedge clk);#1;
    if(!valid || data!==rgb || last!==(col==1279) || user!==((row==0)&&(col==0)))$fatal(1,"axis frame=%d row=%d col=%d last=%b user=%b",frame,row,col,last,user);
    users=users+user;lasts=lasts+last;@(negedge clk);
   end
   de=0;repeat(5)@(negedge clk);
  end
 end
 if(users!=2 || lasts!=6)$fatal;
 $display("PASS HDMI pixel adapter: 7680 pixels, exact SOF and end-of-line markers");$finish;
end
endmodule
