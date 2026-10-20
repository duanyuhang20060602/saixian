`timescale 1ns/1ps
module menu_case #(parameter DELAY=21)(input clk,rst,frame_tick,de,settings_mode,updating,input [11:0] x,input [10:0] y,input [31:0] random_state);
wire [23:0] a,b;
photo_settings_overlay #(.VIDEO_DELAY(DELAY)) actual(clk,rst,frame_tick,de,settings_mode,updating,x,y,random_state[3:0],random_state[7:4],random_state[11:8],random_state[15:12],random_state[19:16],random_state[21:20],random_state[23:22],random_state[24],random_state[25],random_state[30:26],random_state[31],random_state[1],random_state[2],random_state[3],random_state[4],random_state[23:0],a);
photo_settings_overlay_ref #(.VIDEO_DELAY(DELAY)) frozen(clk,rst,frame_tick,de,settings_mode,updating,x,y,random_state[3:0],random_state[7:4],random_state[11:8],random_state[15:12],random_state[19:16],random_state[21:20],random_state[23:22],random_state[24],random_state[25],random_state[30:26],random_state[31],random_state[1],random_state[2],random_state[3],random_state[4],random_state[23:0],b);
always @(posedge clk)begin #1;if(a!==b)$fatal(1,"menu palette mismatch delay=%0d x=%0d y=%0d actual=%h expected=%h",DELAY,x,y,a,b);end
endmodule
module tb;
reg clk=0,rst=1,frame_tick=0,de=0,settings_mode=1,updating=0;always #5 clk=~clk;
reg [11:0] x=0;reg [10:0] y=0;reg [31:0] random_state=32'h9185abcd;integer n;
menu_case normal(clk,rst,frame_tick,de,settings_mode,updating,x,y,random_state);
menu_case #(.DELAY(4)) shortest(clk,rst,frame_tick,de,settings_mode,updating,x,y,random_state);
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(n=0;n<1300000;n=n+1)begin
  @(negedge clk);x=n%1650;y=(n/1650)%750;de=x<1280 && y<720;
  frame_tick=n%32768==0;settings_mode=(n/32768)%9!=8;updating=n%17<5;
  rst=n%217777==100;
  random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
 end
 $display("PASS palette pipeline: 1300000 pixels, all RGB colors, settings snapshots, resets, 4/21-clock latency");$finish;
end
endmodule
