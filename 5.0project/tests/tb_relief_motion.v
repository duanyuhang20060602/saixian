`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=0,pause=0,tick=0,contact=0;
reg[10:0] x=640;reg[9:0] y=360;
wire[4:0] angle;wire signed[5:0] lx,ly;wire update;
wire[4:0] default_angle,old_angle;
photo_relief_motion slow_default(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.touch_contact(contact),.cursor_x(x),.cursor_y(y),.angle(default_angle),.light_x(),.light_y(),.frame_update());
photo_relief_motion #(.HOLD_FRAMES(20)) old_cadence(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.touch_contact(contact),.cursor_x(x),.cursor_y(y),.angle(old_angle),.light_x(),.light_y(),.frame_update());
integer i;reg[4:0] saved;reg signed[5:0] saved_light;
photo_relief_motion #(.HOLD_FRAMES(3)) dut(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),
 .touch_contact(contact),.cursor_x(x),.cursor_y(y),.angle(angle),.light_x(lx),.light_y(ly),.frame_update(update));
task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(4)@(negedge clk);end endtask
initial begin
repeat(3)@(negedge clk);rst=0;enable=1;
for(i=0;i<72;i=i+1)begin frame;if(angle!=((i+1)/3)%24)$fatal(1,"rotation cadence/wrap");end
pause=1;saved=angle;saved_light=lx;
repeat(8)frame;
if(angle!=saved || lx!=saved_light)$fatal(1,"pause did not hold");
contact=1;x=0;y=0;frame;
if(lx!=-20 || ly!=11 || angle!=saved)$fatal(1,"paused interactive light");
x=1279;y=719;repeat(10)@(negedge clk);
if(lx!=-20 || ly!=11)$fatal(1,"mid-frame control change");
frame;if(lx!=19 || ly!=-11)$fatal(1,"pointer range");
enable=0;@(negedge clk);enable=1;pause=0;contact=0;
repeat(3)frame;if(angle!=1)$fatal(1,"reentry rotation");
enable=0;@(negedge clk);enable=1;
for(i=0;i<480;i=i+1)begin
 frame;
 if(default_angle!=((i+1)/10)%24 || old_angle!=((i+1)/20)%24)$fatal(1,"default double-speed cadence %0d",i);
end
$display("PASS exact double-speed default (10 vs 20 frames per angle), automatic rotation, 24-angle wrap, pause, frame-stable pointer light and reentry");$finish;
end
endmodule
