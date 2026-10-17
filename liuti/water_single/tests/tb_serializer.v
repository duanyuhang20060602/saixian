`timescale 1ns/1ps
module tb;
reg pixel=0,serial=0;always #6.665 pixel=~pixel;always #1.333 serial=~serial;
reg pr=1,sr=1;reg[39:0] words=40'h155a5c3e47;wire[3:0] actual,golden;
integer count=0;reg compare=0;
water_hdmi_phy dut(pixel,serial,pr,sr,words[9:0],words[19:10],words[29:20],words[39:30],actual[0],actual[1],actual[2],actual[3]);
hdmi_phy_wrapper reference(pixel,serial,pr,words[9:0],words[19:10],words[29:20],words[39:30],golden[0],golden[1],golden[2],golden[3]);
always @(posedge pixel)words<={words[38:0],words[39]^words[35]^words[20]^words[2]};
always @(posedge serial or negedge serial)begin #0.01;
 if(compare)begin
  if(actual!==golden)$fatal(1,"TMDS serializer mismatch got%b expected%b",actual,golden);
  count=count+4;
 end
end
initial begin
 #100;sr=0;#20;pr=0;#1000;compare=1;#3000;compare=0;
 #0.3;pr=1;sr=1;#130;sr=0;#40;pr=0;#1000;compare=1;#3000;compare=0;
 if(count<16000)$fatal(1,"not enough serial edges");
 $display("PASS TMDS serializer: %0d exact lane bits against vendor, four channels, both DDR edges, independent reset release and restart",count);$finish;
end
endmodule
// Functional DDR output model for lane-order equivalence, not physical timing.
module EG_LOGIC_ODDR(input clk,rst,d0,d1,output reg q);
always @(posedge clk or negedge clk or posedge rst)begin
 if(rst)q<=0;else if(clk)q<=d0;else q<=d1;
end
endmodule
