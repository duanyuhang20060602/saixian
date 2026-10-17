module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,ready=0;reg[1:0] buffer=0;
wire[1:0] current,next;wire commit,valid,active,right;wire[3:0] mode;wire[10:0] offset;wire[5:0] dark;wire[8:0] progress;
water_transition d(.clk(clk),.rst(rst),.frame_tick(tick),.frame_ready_toggle(ready),.ready_buf_idx(buffer),.ready_slide_right(1'b0),
 .active_buf_idx(current),.slide_new_buf_idx(next),.frame_commit_toggle(commit),.display_valid(valid),.transition_active(active),
 .transition_mode(mode),.slide_offset(offset),.slide_right(right),.transition_level(dark),.water_progress(progress));
task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
integer i,n,expected;reg old_commit;integer last_phase;
initial begin
 repeat(4)@(negedge clk);rst=0;ready=1;repeat(4)@(negedge clk);frame;
 if(!valid||active||current!=0)$fatal(1,"initial frame handshake failed");
 for(i=0;i<33;i=i+1)begin
  buffer=(i+1)%4;ready=~ready;repeat(4)@(negedge clk);old_commit=commit;frame;
  case(i%11)0:expected=6;1:expected=0;2:expected=1;3:expected=2;4:expected=3;5:expected=4;6:expected=5;7:expected=7;8:expected=8;9:expected=9;default:expected=10;endcase
  if(!active||mode!=expected||commit!=old_commit)$fatal(1,"transition launch %0d mode%0d",i,mode);
  n=0;last_phase=0;
  while(active&&n<80)begin
   frame;n=n+1;
   if(active)begin if(progress<last_phase||progress>256)$fatal(1,"water phase invalid");last_phase=progress;end
  end
  if(active||commit==old_commit||current!=buffer)$fatal(1,"frame commit failed %0d",i);
  if(last_phase!=256)$fatal(1,"water transition did not display a complete destination before commit: %0d",last_phase);
  if(n!=36)$fatal(1,"water duration wrong %0d",n);
 end
 $display("PASS eleven showcase transitions over three cycles, all 36-frame animations, stable source ownership and commit");$finish;
end
endmodule
