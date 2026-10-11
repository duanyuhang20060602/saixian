`timescale 1ns/1ps
module tb_key2_tf_flow;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,short_press=0,long_press=0,stop=0,blue=0,red=0,sprint=0;
wire busy,tf,sprint_active,trigger,choose_blue,choose_red;
saixian_key2_result_router router(1'b1,busy,short_press,long_press,trigger,choose_blue,choose_red);
saixian_battle_result_fx #(.TF_ANIMATION_ENABLE(1),.AUTO_SPRINT_PODIUM(1)) dut(
 .clk(clk),.rst(rst),.frame_tick(ft),.trigger(trigger),.stop(stop),
 .select_blue(blue|choose_blue),.select_red(red|choose_red),.select_sprint(sprint),
 .x_in(11'd0),.y_in(10'd0),.de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0),
 .sprint_background_valid(1'b1),.busy(busy),.sprint_active(sprint_active),.tf_active(tf),
 .de_out(),.vs_out(),.rgb_out());
task tick;begin @(negedge clk);ft=1;@(negedge clk);ft=0;end endtask
task press;begin @(negedge clk);short_press=1;@(negedge clk);short_press=0;end endtask
task reset;begin @(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;end endtask
task settle_sprint;begin
 repeat(144)tick;if(dut.state!=4)$fatal(1,"ranking entrance failed");
 press;tick;if(dut.state!=5)$fatal(1,"manual podium continue lost");
 repeat(96)tick;if(dut.state!=6)$fatal(1,"podium entrance failed");
end endtask
integer winner;
initial begin
 reset;
 for(winner=0;winner<2;winner=winner+1)begin
  if(winner==0)press;
  else begin @(negedge clk);long_press=1;@(negedge clk);long_press=0;end
  if(!busy)$fatal(1,"winner command not latched");
  tick;if(dut.state!=(winner==0?1:7))$fatal(1,"wrong winner");
  press;tick;repeat(359)tick;
  if(dut.state!=(winner==0?2:8))$fatal(1,"transition key skipped victory");
  press;if(tf)$fatal(1,"victory jumped into TF");tick;
  if(dut.state!=3 || !sprint_active)$fatal(1,"winner continue lost sprint");
  press;tick;repeat(143)tick;
  if(dut.state!=4)$fatal(1,"early key skipped ranking");
  repeat(120)tick;if(dut.state!=5)$fatal(1,"automatic podium missing");
  press;tick;repeat(95)tick;
  if(dut.state!=6 || tf)$fatal(1,"early key queued TF start");
  press;if(tf)$fatal(1,"TF changed outside frame boundary");tick;
  if(!tf || !busy || sprint_active)$fatal(1,"podium key did not enter TF");
  repeat(25)tick;if(!tf)$fatal(1,"TF mode did not hold for looping");
  press;tick;if(tf || busy)$fatal(1,"TF key did not return to carousel");
 end
 sprint=1;tick;sprint=0;repeat(144+120+96)tick;
 if(dut.state!=6)$fatal(1,"HMI direct sprint flow changed");
 press;tick;if(!tf)$fatal(1,"HMI sprint cannot continue into TF");
 stop=1;@(negedge clk);stop=0;if(!tf)$fatal(1,"stop changed mid-frame");
 tick;if(tf || busy)$fatal(1,"HMI stop cannot exit TF");
 blue=1;tick;blue=0;stop=1;tick;stop=0;
 if(busy)$fatal(1,"stop cannot exit victory");
 $display("PASS blue/red victory -> automatic sprint/podium -> KEY2 TF loop -> KEY2 exit; early presses ignored; HMI stop");$finish;
end
endmodule
