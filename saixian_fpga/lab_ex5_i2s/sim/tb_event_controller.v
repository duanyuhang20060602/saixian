`timescale 1ns/1ps
module tb_event_controller;
reg clk=0, rst=1, frame_start=1;
reg key_start=0, key_pause=0, key_end=0;
reg [1:0] project_switch=2'd2;
wire [3:0] state, countdown_value, cue_event;
wire [1:0] project_id;
wire [6:0] minutes;
wire [5:0] seconds;
wire carousel_mode;

always #5 clk=~clk;
saixian_event_controller #(.CLK_FREQ_HZ(10)) dut(
 .clk(clk),.rst(rst),.frame_start(frame_start),.key_start(key_start),.key_pause(key_pause),.key_end(key_end),
 .project_switch(project_switch),.state(state),.project_id(project_id),.minutes(minutes),.seconds(seconds),
 .countdown_value(countdown_value),.cue_event(cue_event),.carousel_mode(carousel_mode));

task press_start; begin @(negedge clk); key_start=1; @(negedge clk); key_start=0; end endtask
task press_pause; begin @(negedge clk); key_pause=1; @(negedge clk); key_pause=0; end endtask
task press_end; begin @(negedge clk); key_end=1; @(negedge clk); key_end=0; end endtask
task expect_state; input [3:0] wanted; begin
  if (state !== wanted) begin $display("FAIL state=%0d wanted=%0d",state,wanted); $finish; end
end endtask

initial begin
 repeat(3) @(posedge clk); rst=0;
 press_start; repeat(2) @(posedge clk); expect_state(1); if(project_id!==2) $finish;
 press_start; repeat(2) @(posedge clk); expect_state(2); if(countdown_value!==3) $finish;
 repeat(11) @(posedge clk); expect_state(3);
 repeat(10) @(posedge clk); expect_state(4);
 repeat(10) @(posedge clk); expect_state(5);
 repeat(10) @(posedge clk); expect_state(6);
 repeat(12) @(posedge clk); if(seconds<1) $finish;
 press_pause; repeat(2) @(posedge clk); expect_state(7);
 press_pause; repeat(2) @(posedge clk); expect_state(6);
 press_end; repeat(2) @(posedge clk); expect_state(8);
 repeat(31) @(posedge clk); expect_state(0);
 $display("PASS tb_event_controller"); $finish;
end
endmodule
