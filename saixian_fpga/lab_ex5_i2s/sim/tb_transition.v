`timescale 1ns/1ps
module tb_transition;
reg clk=0,rst=1,frame_tick=0,frame_ready_toggle=0,ready_slide_right=0;
reg [1:0] ready_buf_idx=0;
wire [1:0] active_buf_idx,slide_new_buf_idx;
wire frame_commit_toggle,display_valid,transition_active,slide_right;
wire [9:0] slide_offset;
wire [5:0] transition_level;
always #5 clk=~clk;
saixian_transition dut(.*);
task frame; begin @(negedge clk); frame_tick=1; @(negedge clk); frame_tick=0; end endtask
integer i;
initial begin
    repeat(3) @(posedge clk); rst=0;

    // First image commits immediately because there is no previous frame.
    ready_buf_idx=0; frame_ready_toggle=1; repeat(3) @(posedge clk); frame;
    if(active_buf_idx!==0 || !display_valid || transition_active || frame_commit_toggle!==1) begin
        $display("FAIL initial commit"); $finish;
    end

    // Next image pushes left and reaches the midpoint after eight frames.
    ready_buf_idx=1; ready_slide_right=0; frame_ready_toggle=0; repeat(3) @(posedge clk); frame;
    if(!transition_active || slide_right || slide_new_buf_idx!==1) begin
        $display("FAIL left start"); $finish;
    end
    for(i=0;i<8;i=i+1) frame;
    if(slide_offset!==320) begin $display("FAIL midpoint %0d",slide_offset); $finish; end
    for(i=0;i<8;i=i+1) frame;
    if(slide_offset!==640 || !transition_active) begin $display("FAIL left end"); $finish; end
    frame;
    if(active_buf_idx!==1 || transition_active || frame_commit_toggle!==0) begin
        $display("FAIL left commit"); $finish;
    end

    // Previous image pushes right.
    ready_buf_idx=0; ready_slide_right=1; frame_ready_toggle=1; repeat(3) @(posedge clk); frame;
    if(!transition_active || !slide_right || slide_new_buf_idx!==0) begin
        $display("FAIL right start"); $finish;
    end
    for(i=0;i<16;i=i+1) frame;
    frame;
    if(active_buf_idx!==0 || transition_active || frame_commit_toggle!==1) begin
        $display("FAIL right commit"); $finish;
    end

    $display("PASS tb_transition"); $finish;
end
endmodule
