`timescale 1ns/1ps
module tb_result_controls;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,trigger=0,blue=0,red=0,sprint=0,stop=0;
wire busy,sprint_active,de,vs;wire [23:0] rgb;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(ft),.trigger(trigger),
 .stop(stop),.select_blue(blue),.select_red(red),.select_sprint(sprint),
 .x_in(11'd0),.y_in(10'd0),.de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0),
 .sprint_background_valid(1'b1),.busy(busy),.sprint_active(sprint_active),
 .de_out(de),.vs_out(vs),.rgb_out(rgb));
task tick;begin @(negedge clk);ft=1;@(negedge clk);ft=0;end endtask
initial begin
 repeat(3) @(negedge clk);rst=0;
 blue=1;@(negedge clk);blue=0;
 repeat(3) @(negedge clk);if(dut.state!=0) $fatal(1,"blue changed mid-frame");
 tick;if(dut.state!=1) $fatal(1,"blue command lost");
 red=1;@(negedge clk);red=0;
 repeat(3) @(negedge clk);if(dut.state!=1) $fatal(1,"red changed mid-frame");
 tick;if(dut.state!=7) $fatal(1,"red command lost");
 sprint=1;@(negedge clk);sprint=0;
 repeat(3) @(negedge clk);if(sprint_active) $fatal(1,"sprint changed mid-frame");
 tick;if(dut.state!=3 || !sprint_active) $fatal(1,"sprint command lost");
 trigger=1;@(negedge clk);trigger=0;tick;
 if(dut.state!=3) $fatal(1,"entrance skipped by button");
 repeat(144) tick;if(dut.state!=4) $fatal(1,"rank did not settle");
 repeat(120) tick;if(dut.state!=5) $fatal(1,"automatic podium missing");
 repeat(96) tick;if(dut.state!=6) $fatal(1,"podium did not settle");
 trigger=1;tick;trigger=0;if(dut.state!=0) $fatal(1,"carousel return failed");
 blue=1;tick;blue=0;stop=1;@(negedge clk);stop=0;
 if(!busy)$fatal(1,"Stop must wait for frame boundary");
 tick;if(busy || dut.state!=0)$fatal(1,"Stop did not exit blue entrance");
 blue=1;tick;blue=0;
 repeat(360) tick;if(dut.state!=2)$fatal(1,"blue victory did not settle");
 trigger=1;tick;trigger=0;
 if(dut.state!=3)$fatal(1,"blue continue must skip red victory and enter ranking");
 stop=1;tick;stop=0;if(busy)$fatal(1,"Stop did not exit blue-to-ranking flow");
 red=1;tick;red=0;
 repeat(360) tick;if(dut.state!=8)$fatal(1,"red victory did not settle");
 trigger=1;tick;trigger=0;
 if(dut.state!=3)$fatal(1,"red continue did not enter ranking");
 stop=1;tick;stop=0;if(busy)$fatal(1,"Stop did not exit red-to-ranking flow");
 sprint=1;tick;sprint=0;stop=1;tick;stop=0;
 if(busy || sprint_active)$fatal(1,"Stop did not exit sprint entrance");
 stop=1;tick;stop=0;tick;if(busy)$fatal(1,"Repeated stop restarted result");
 $display("PASS blue skips red, direct red continues to ranking, sprint protection, podium, carousel return");$finish;
end
endmodule
