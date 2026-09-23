`timescale 1ns/1ps
module tb_blue_victory;
reg clk=0; always #5 clk=~clk;
reg rst=1,frame_tick=0,trigger=0,de=0,vs=0;
reg [10:0] x=0; reg [9:0] y=0;
reg [23:0] rgb=24'h123456;
wire busy,deo,vso; wire [23:0] out;
saixian_battle_result_fx dut(clk,rst,frame_tick,trigger,x,y,de,vs,rgb,busy,deo,vso,out);
task step; begin @(posedge clk); #1; end endtask
task frame; begin @(negedge clk);frame_tick=1;step;@(negedge clk);frame_tick=0;step;end endtask
task press; begin @(negedge clk);trigger=1;step;@(negedge clk);trigger=0;step;end endtask
task check; input ok; input [511:0] message; begin if(!ok) begin $display("FAIL: %s",message);$fatal(1);end end endtask
integer i,j,f;
initial begin
step;step;@(negedge clk);rst=0;step;
check(!busy,"reset returns idle");
de=1;vs=1; repeat(4) step;
check(deo && vso && out==24'h123456,"idle passthrough and sync");
press;check(busy && dut.state==0,"press queues until frame boundary");
frame;check(dut.state==1 && dut.frame_count==0,"start on frame boundary");
repeat(40) frame;
press;check(dut.pending==0,"ignore press during PLAY");
repeat(320) frame;
check(dut.state==2 && dut.frame_count==359 && busy,"360 frames reaches HOLD");
repeat(600) frame;
check(dut.state==2 && dut.frame_count==359 && busy,"HOLD stays indefinitely");
f=$fopen("doc/hmi_ui/blue_victory_rtl.ppm","wb");
$fwrite(f,"P6\n1280 720\n255\n");
for(j=0;j<720;j=j+1) for(i=0;i<1280;i=i+1) begin
 @(negedge clk);x=i;y=j;de=1;vs=0;
 repeat(3) step;
 $fwrite(f,"%c%c%c",out[23:16],out[15:8],out[7:0]);
end
$fclose(f);
press;check(dut.state==2,"exit waits frame boundary");
frame;check(dut.state==0 && !busy,"K2 exits HOLD");
repeat(4) step;check(out==24'h123456,"carousel pixels restored");
@(negedge clk);trigger=1;frame_tick=1;step;
@(negedge clk);trigger=0;frame_tick=0;step;
check(dut.state==1 && dut.frame_count==0,"same-cycle trigger/frame works");
repeat(359) frame;
press;frame;
check(dut.state==2 && !dut.pending,"last PLAY press does not exit HOLD");
rst=1;step;check(!busy,"reset clears hold");
$display("PASS: idle, queued start, PLAY ignore, 360-frame HOLD, 600-frame persistence, exit, replay, reset");
$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule

