`timescale 1ns/1ps
module tb_transition;
reg clk=0,rst=1,frame_tick=0,frame_ready_toggle=0;
reg [1:0] ready_buf_idx=0;
wire [1:0] active_buf_idx;
wire frame_commit_toggle,display_valid,transition_active;
wire [5:0] transition_level;
always #5 clk=~clk;
saixian_transition dut(.*);
task frame; begin @(negedge clk); frame_tick=1; @(negedge clk); frame_tick=0; end endtask
integer i;
initial begin
 repeat(3) @(posedge clk); rst=0;
 ready_buf_idx=1; frame_ready_toggle=1; repeat(3) @(posedge clk);
 for(i=0;i<17;i=i+1) frame;
 if(active_buf_idx!==1 || !display_valid || frame_commit_toggle!==1) $finish;
 for(i=0;i<17;i=i+1) frame;
 if(transition_active || transition_level!==0) $finish;
 $display("PASS tb_transition"); $finish;
end
endmodule
