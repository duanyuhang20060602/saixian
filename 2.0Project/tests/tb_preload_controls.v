`timescale 1ns/1ps
module tb_preload_controls;
reg clk=0,rst=1,tick=0,trigger=0,ready=0,stop=0;
wire busy,sprint,request,show;
always #5 clk=~clk;
saixian_battle_result_fx #(.TF_ANIMATION_ENABLE(1),.AUTO_SPRINT_PODIUM(1),.TF_READY_GATED(1)) dut(
 .clk(clk),.rst(rst),.frame_tick(tick),.trigger(trigger),.select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(stop),
 .x_in(11'd0),.y_in(10'd0),.de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b1),
 .busy(busy),.sprint_active(sprint),.tf_active(request),.tf_ready(ready),.tf_display(show));
task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 @(negedge clk);dut.state=6;dut.result_frame=95;dut.red_selected=1;
 trigger=1;frame;trigger=0;
 if(!busy || !request || show || !sprint || dut.result_frame!=95 || !dut.red_selected)$fatal(1,"podium lost while loading");
 repeat(5)frame;
 if(show || dut.state!=10 || dut.result_frame!=95)$fatal(1,"unready animation selected");
 ready=1;frame;
 if(!show || !request || sprint)$fatal(1,"ready animation not selected");
 trigger=1;frame;trigger=0;
 if(show || request || busy)$fatal(1,"exit did not return carousel");
 @(negedge clk);dut.state=6;dut.result_frame=95;ready=0;trigger=1;frame;trigger=0;
 trigger=1;frame;trigger=0;
 if(request || show || busy)$fatal(1,"loading cancel failed");
 @(negedge clk);dut.state=10;stop=1;frame;stop=0;
 if(request || busy)$fatal(1,"HMI stop failed while loading");
 $display("PASS preload controls: retain red/blue podium pose until ready, KEY2 exit/cancel, HMI stop");$finish;
end
endmodule
