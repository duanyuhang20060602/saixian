`timescale 1ns/1ps
module tb_fade_no_flash;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,ready=0;wire active,valid;wire [10:0] offset;wire [5:0] level;
reg [2:0] selection=6;wire [2:0] mode;wire [23:0] output_rgb;
saixian_transition transition(.clk(clk),.rst(rst),.frame_tick(tick),.frame_ready_toggle(ready),.ready_buf_idx(2'd1),
 .ready_slide_right(1'b0),.ready_immediate(1'b0),.effect_select(selection),.transition_active(active),.display_valid(valid),
 .slide_offset(offset),.transition_level(level),.transition_mode(mode));
wire [23:0] input_rgb=offset<640 ? 24'hff4020:24'h20c0ff;
photo_display_fade fade(.clk(clk),.rst(rst),.darkness(level),.rgb_in(input_rgb),.rgb_out(output_rgb));
task frame;
 begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(10)@(negedge clk);end
endtask
integer i,e,black_frames=0;reg [5:0] old_level;
initial begin
 repeat(5)@(negedge clk);rst=0;ready=1;repeat(5)@(negedge clk);frame();if(!valid)$fatal(1,"initial photo");
 ready=0;repeat(5)@(negedge clk);frame();if(!active || mode!=5)$fatal(1,"fade did not start");
 old_level=0;
 for(i=1;i<=16;i=i+1)begin
  frame();
  if(i<8 && level<old_level)$fatal(1,"fade out not monotonic");
  if(i>9 && level>old_level)$fatal(1,"fade in not monotonic");
  if(i>=7 && i<=9)begin
   if(level!=63 || output_rgb!==24'h101010)$fatal(1,"lit pixel at old/new handover step %0d rgb=%h level=%0d",i,output_rgb,level);
   black_frames=black_frames+1;
  end
  if(i==16 && output_rgb!==24'h2bb4ea)$fatal(1,"final photo brightness mismatch %h",output_rgb);
  old_level=level;
 end
 frame();if(active || level!=0 || black_frames!=3)$fatal(1,"fade completion");
 // Named effects must survive without a high-colour forced-fade override.
 for(e=1;e<=6;e=e+1)begin
  selection=e;ready=~ready;repeat(5)@(negedge clk);frame();if(mode!=e-1)$fatal(1,"effect selection %0d",e);
  repeat(17)frame();if(active)$fatal(1,"effect completion %0d",e);
 end
 $display("PASS fade: one smooth gain, true-black old/new handover, restored final brightness, all effect selections");$finish;
end
endmodule
