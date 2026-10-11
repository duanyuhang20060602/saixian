`timescale 1ns/1ps
module tb_video_latency;
reg clk=0;always #5 clk=~clk;
reg rst=1,publish=0;
wire [23:0] rgb;wire de,vs,pop,commit,frame,slot,valid,underrun;
wire [15:0] p0={dut.h[4:0],dut.v[5:0],dut.h[3:0],1'b0};
wire [15:0] p1={~dut.h[4:0],dut.v[5:0],~dut.h[3:0],1'b0};
wire [31:0] head={p1,p0};
delta_video #(.SCENE_WIDTH(1280),.SCENE_HEIGHT(720),.LIVE_AWARD(1)) dut(
 clk,rst,publish,1'b0,head,1'b0,pop,rgb,de,vs,commit,frame,slot,valid,underrun,1'b1);
reg [23:0] expected[0:5];reg [5:0] expected_de=0,expected_vs=0;
reg [23:0] sampled;reg sampled_de,sampled_vs;integer i,cycles=0,pixels=0;
initial begin for(i=0;i<6;i=i+1)expected[i]=0;repeat(5)@(negedge clk);rst=0;publish=1;end
always @(posedge clk)begin
 if(!rst)begin
  sampled_de=dut.de;sampled_vs=dut.v<5;
  sampled=dut.scene ? dut.expanded : 24'd0;
  for(i=5;i>0;i=i-1)expected[i]=expected[i-1];expected[0]=sampled;
  expected_de={expected_de[4:0],sampled_de};expected_vs={expected_vs[4:0],sampled_vs};
  #1;
  if(cycles>=6)begin
   if(de!==expected_de[5]||vs!==expected_vs[5])$fatal(1,"HDMI DE/VS latency mismatch");
   if(rgb!==expected[5])$fatal(1,"RGB latency mismatch cycle %0d got %h expected %h",cycles,rgb,expected[5]);
   if(valid&&de)pixels=pixels+1;
  end
  cycles=cycles+1;
  if(pixels==921600)begin
   if(underrun)$fatal(1,"Unexpected underrun");
   $display("PASS video_latency: 921600 exact RGB pixels, first/last pixels and HDMI DE/VS aligned through five-stage effects");$finish;
  end
  if(cycles>2600000)$fatal(1,"video latency timeout");
 end
end
endmodule
