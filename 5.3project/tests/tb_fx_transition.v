`timescale 1ns/1ps
module tb_fx_transition;
reg clk=0;always #5 clk=~clk;
reg rst=1,ready=0,immediate=0;reg [4:0] selection=0;
wire active,valid,commit,page;wire [4:0] mode;wire [3:0] style;
integer i,events=0;
saixian_transition #(.ALLOW_IMMEDIATE(1)) transition(.clk(clk),.rst(rst),.frame_tick(1'b1),.fluid_enable(1'b1),.frame_ready_toggle(ready),.ready_buf_idx(2'd1),.ready_slide_right(1'b1),.ready_immediate(immediate),.effect_select(selection),.display_valid(valid),.transition_active(active),.transition_mode(mode),.frame_commit_toggle(commit));
photo_transition_page_event detector(.clk(clk),.rst(rst),.enable(1'b1),.display_valid(valid),.transition_active(active),.image(3'd0),.count(3'd6),.transition_mode(mode),.page_event(page),.page_style(style));
always @(negedge clk)if(page)begin
 if(!active || style!==mode)$fatal(1,"page sound not aligned with actual selected mode");
 events=events+1;
end
initial begin
 repeat(3)@(negedge clk);rst=0;ready=1;wait(valid);repeat(5)@(negedge clk);
 if(events!=0)$fatal(1,"initial picture sounded");
 for(i=0;i<24;i=i+1)begin
  @(negedge clk);selection=i<12 ? i:0;ready=~ready;
  wait(active);wait(!active);repeat(5)@(negedge clk);
  if(events!=i+1)$fatal(1,"missing/duplicate transition sound");
 end
 immediate=1;ready=~ready;repeat(10)@(negedge clk);
 if(events!=24)$fatal(1,"immediate same-photo refresh sounded");
 $display("PASS real transition integration: fixed selections 1..11, actual random modes, sound at start once, initial and immediate refresh silent");$finish;
end
initial begin #1000000;$fatal(1,"transition integration timeout");end
endmodule
