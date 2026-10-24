`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,ready=0,fluid_enable=1,immediate=0;
reg[1:0] next_slot=1;reg[4:0] selection=0;
wire active,valid,commit;wire[10:0] offset;wire[8:0] progress;
wire[5:0] level;wire[4:0] mode;wire[1:0] current;
saixian_transition #(.ALLOW_IMMEDIATE(1)) transition(.fluid_enable(fluid_enable),.clk(clk),.rst(rst),
 .frame_tick(tick),.frame_ready_toggle(ready),.ready_buf_idx(next_slot),.ready_slide_right(1'b0),
 .ready_immediate(immediate),.effect_select(selection),.transition_active(active),.display_valid(valid),
 .slide_offset(offset),.transition_level(level),.transition_mode(mode),.fluid_progress(progress),
 .active_buf_idx(current),.frame_commit_toggle(commit));
task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(8)@(negedge clk);end endtask
task submit;begin ready=~ready;repeat(5)@(negedge clk);frame();end endtask
integer i,e,n;reg[8:0] previous;reg saved_commit;reg[10:0] seen=0;reg[4:0] last_mode=31;
function[4:0] expected;input integer v;begin
 case(v)1:expected=6;2:expected=0;3:expected=1;4:expected=2;5:expected=3;6:expected=4;
 7:expected=5;8:expected=7;9:expected=8;10:expected=9;11:expected=10;default:expected=0;endcase
end endfunction
task finish_transition;begin
 previous=0;saved_commit=commit;
 for(i=1;i<=48;i=i+1)begin
  frame();
  if(!active||progress<previous||progress>256||level!=0||commit!=saved_commit)$fatal(1,"invalid 48-frame progression");
  previous=progress;
 end
 if(progress!=256||offset!=1280)$fatal(1,"missing complete destination endpoint");
 frame();if(active||progress!=0||current!=next_slot||commit==saved_commit)$fatal(1,"commit did not follow endpoint");
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;submit();if(!valid||active||current!=next_slot)$fatal(1,"first image must be immediate");
 for(e=1;e<=11;e=e+1)begin
  selection=e;next_slot=next_slot==2 ? 0:next_slot+1'b1;submit();
  if(!active||mode!=expected(e)||progress!=0)$fatal(1,"effect selection %0d",e);
  finish_transition();
 end
 selection=0;
 for(n=0;n<80;n=n+1)begin
  repeat(n%3)frame();submit();
  if(mode>10||mode==last_mode)$fatal(1,"invalid or repeated random effect");
  seen[mode]=1;last_mode=mode;finish_transition();
 end
 if(seen!=11'h7ff)$fatal(1,"random mode does not cover all eleven effects: %h",seen);
 fluid_enable=0;
 for(e=1;e<=11;e=e+1)begin selection=e;submit();if(mode!=0)$fatal(1,"RGB888 fallback");finish_transition();end
 immediate=1;next_slot=2;submit();if(active||current!=2)$fatal(1,"immediate award/settings commit");
 $display("PASS 48-frame progression, eleven fixed effects, random coverage/no repeats, native endpoint commit, RGB888 fallback and immediate updates");$finish;
end
initial begin #3000000;$fatal(1,"transition timeout");end
endmodule
