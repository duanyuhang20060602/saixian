module photo_match_manager #(parameter HZ=75000000,DB_CYCLES=1500000,HOLD_CYCLES=75000000,SHARED_TIMEOUT=0)(
 input clk,rst,frame_tick,entry_allowed,input[3:0] key_n,
 input byte_valid,input[7:0] byte_data,input serial_idle,text_active,serial_timeout,
 output reg active,output serial_busy,output[3:0] photo_key_n,
 output[2:0] state,team_a,team_b,output[9:0] score_a,score_b,output[8:0] remaining,
 output[1:0] duration_index,countdown,output[3:0] cue_event,output serial_error,
 output[3:0] photo_press,output photo_short,photo_long);
wire command_valid;wire[3:0] operation;wire[9:0] value;
photo_match_serial #(.HZ(HZ),.SHARED_TIMEOUT(SHARED_TIMEOUT)) serial(.shared_timeout(serial_timeout),.clk(clk),.rst(rst),.byte_valid(byte_valid),.byte_data(byte_data),
 .can_start(serial_idle && !text_active),.busy(serial_busy),.valid(command_valid),
 .operation(operation),.value(value),.error(serial_error));
wire[3:0] short_key,long_key,synchronized_key_n,pressed_key;
reg previous_active;
always @(posedge clk or posedge rst)if(rst)previous_active<=0;else previous_active<=active;
// Both modes share debounce and long-press time bases. Exit is guarded until
// the new key context has consumed held gestures. Photo presses occur on down.
assign photo_press=pressed_key & {4{!active && !previous_active}};
assign photo_short=short_key[3] && !active && !previous_active;
assign photo_long=long_key[3] && !active && !previous_active;
photo_match_keys #(.CLK_HZ(HZ),.DB_CYCLES(DB_CYCLES),.HOLD_CYCLES(HOLD_CYCLES),.TICK_DIV(HZ>=1000000 ? HZ/1000:1)) keys(
 .clk(clk),.rst(rst),.key_n(key_n),.key_scene(active ? state:3'd7),
 .short_key(short_key),.long_key(long_key),.synchronized_key_n(synchronized_key_n),.press_key(pressed_key));
reg wanted,pending;reg[3:0] return_block;
always @(posedge clk or posedge rst)
 if(rst)begin active<=0;wanted<=0;pending<=0;return_block<=0;end
 else begin
  if(active)return_block<=~synchronized_key_n;
  else return_block<=return_block & ~synchronized_key_n;
  if(frame_tick && pending && (!wanted || entry_allowed))begin active<=wanted;pending<=0;end
  if(active && state==0 && long_key[3])begin wanted<=0;pending<=1;end
  if(command_valid && operation==0)begin wanted<=value[0];pending<=1;end
 end
assign photo_key_n=key_n | {4{active}} | return_block;
reg[3:0] remote_short,remote_long;
always @*begin
 remote_short=0;remote_long=0;
 if(command_valid && active && operation==1)case(value)
  0:if(state==0)remote_short[3]=1;
  1:if(state==2 || state==3)remote_short[2]=1;
  2:if(state==1 || state==2 || state==3)remote_long[3]=1;
  3:if(state==4)remote_short[3]=1;
  4:if(state==2 || state==3)remote_short[0]=1;5:remote_long[0]=1;
  6:if(state==2 || state==3)remote_short[1]=1;7:remote_long[1]=1;
 endcase
end
photo_match_control #(.CLK_HZ(HZ)) control(.clk(clk),.rst(rst || !active),
 .short_key(short_key | remote_short),.long_key(long_key | remote_long),
 .state(state),.team_a(team_a),.team_b(team_b),.score_a(score_a),.score_b(score_b),
 .remaining(remaining),.duration_index(duration_index),.countdown(countdown),.cue_event(cue_event),
 .remote_valid(command_valid && active),.remote_operation(operation),.remote_value(value));
endmodule
