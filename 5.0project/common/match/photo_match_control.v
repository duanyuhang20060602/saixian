`timescale 1ns/1ps
// Same-domain controller, intentionally independent of HDMI/SDRAM.
module photo_match_control #(parameter CLK_HZ=75000000)(
 input clk,rst,input [3:0] short_key,long_key,
 output reg [2:0] state,team_a,team_b,
 output reg [9:0] score_a,score_b,output reg [8:0] remaining,
 output reg [1:0] duration_index,countdown,
 output reg [3:0] cue_event,
 input remote_valid,input [3:0] remote_operation,input [9:0] remote_value
);
localparam SETUP=0,COUNT=1,RUN=2,PAUSE=3,RESULT=4;
reg [26:0] second_count;
wire tick=second_count==CLK_HZ-1;
function [8:0] duration;input [1:0] i;begin
 case(i)0:duration=30;1:duration=60;2:duration=180;default:duration=300;endcase
end endfunction
function [2:0] next_team;input [2:0] now,other;reg [2:0] n;begin
 n=now==5 ? 0:now+1'b1;
 next_team=n==other ? (n==5 ? 0:n+1'b1):n;
end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=SETUP;team_a<=0;team_b<=1;score_a<=0;score_b<=0;
  duration_index<=0;remaining<=30;countdown<=0;second_count<=0;cue_event<=0;end
 else begin
  cue_event<=0;
  if(state==COUNT || state==RUN)second_count<=tick ? 0:second_count+1'b1;
  else second_count<=0;
  case(state)
   SETUP:begin
    if(!(remote_valid && (remote_operation==2 || remote_operation==3 || remote_operation==6)))begin
    if(short_key[0])team_a<=next_team(team_a,team_b);
    // Serialize simultaneous selections, so the two names cannot coincide.
    if(short_key[1] && !short_key[0])team_b<=next_team(team_b,team_a);
    if(short_key[2])begin duration_index<=duration_index+1'b1;remaining<=duration(duration_index+1'b1);end
    if(short_key[3] && !short_key[2])begin
     score_a<=0;score_b<=0;remaining<=duration(duration_index);countdown<=3;
     state<=COUNT;second_count<=0;cue_event<=1;
    end
    end
   end
   COUNT:begin
    if(long_key[3])begin state<=SETUP;second_count<=0;countdown<=0;end
    else if(tick)begin
     if(countdown==1)begin state<=RUN;countdown<=0;cue_event<=2;end
     else begin countdown<=countdown-1'b1;cue_event<=1;end
    end
   end
   RUN,PAUSE:begin
    if(long_key[0])begin if(score_a!=0)score_a<=score_a-1'b1;end
    else if(short_key[0] && score_a<999)score_a<=score_a+1'b1;
    if(long_key[1])begin if(score_b!=0)score_b<=score_b-1'b1;end
    else if(short_key[1] && score_b<999)score_b<=score_b+1'b1;
    if(long_key[3])begin state<=RESULT;cue_event<=5;second_count<=0;end
    else if(short_key[2])begin
     state<=state==RUN ? PAUSE:RUN;cue_event<=state==RUN ? 3:4;
     // Pause freezes the fractional second, so repeated pauses cannot add time.
     second_count<=second_count;
    end else if(state==RUN && tick)begin
     if(remaining<=1)begin remaining<=0;state<=RESULT;cue_event<=5;end
     else begin remaining<=remaining-1'b1;if(remaining<=11)cue_event<=1;end
    end
   end
   RESULT:if(short_key[3])begin state<=SETUP;remaining<=duration(duration_index);score_a<=0;score_b<=0;end
   default:state<=SETUP;
  endcase
  // Serial-screen corrections win simultaneous physical corrections.
  if(remote_valid)begin
   if(state==SETUP)case(remote_operation)
    2:if(remote_value<6 && remote_value!=team_b)team_a<=remote_value[2:0];
    3:if(remote_value<6 && remote_value!=team_a)team_b<=remote_value[2:0];
    6:if(remote_value<4)begin duration_index<=remote_value[1:0];remaining<=duration(remote_value[1:0]);end
   endcase
   if(state==RUN || state==PAUSE)case(remote_operation)
    4:if(remote_value<=999)score_a<=remote_value;
    5:if(remote_value<=999)score_b<=remote_value;
   endcase
  end
  if(state==PAUSE && !long_key[3] && !short_key[2])second_count<=second_count;
 end
end
endmodule

// A held key emits one long event and no short event on release. Context
// changes consume all held keys; a start/finish gesture cannot leak next game.
module photo_match_keys #(parameter CLK_HZ=75000000,DB_CYCLES=1500000,HOLD_CYCLES=75000000,TICK_DIV=1)(
 input clk,rst,input [3:0] key_n,input [2:0] key_scene,
 output reg [3:0] short_key,long_key,output [3:0] synchronized_key_n,output reg[3:0] press_key
);
(* async_reg="true" *)reg [3:0] meta,sync;
reg [3:0] stable,fired,blocked;
localparam DB_TICKS=(DB_CYCLES+TICK_DIV-1)/TICK_DIV+(TICK_DIV>1 ? 1:0);
localparam HOLD_TICKS=(HOLD_CYCLES+TICK_DIV-1)/TICK_DIV;
localparam DBW=DB_TICKS>1 ? $clog2(DB_TICKS):1;
localparam HW=HOLD_TICKS>1 ? $clog2(HOLD_TICKS):1;
wire key_tick;
generate if(TICK_DIV==1)begin:every_clock
 assign key_tick=1'b1;
end else begin:millisecond
 localparam DW=$clog2(TICK_DIV);
 reg[DW-1:0] divider;
 assign key_tick=divider==TICK_DIV-1;
 always @(posedge clk or posedge rst)
  if(rst)divider<=0;else if(key_tick)divider<=0;else divider<=divider+1'b1;
end endgenerate
reg [DBW-1:0] db[0:3];reg [HW-1:0] hold[0:3];reg [2:0] old_key_scene;
assign synchronized_key_n=sync;
integer k;
always @(posedge clk or posedge rst)begin
 if(rst)begin meta<=15;sync<=15;stable<=15;fired<=0;blocked<=15;
  short_key<=0;long_key<=0;press_key<=0;old_key_scene<=0;
  for(k=0;k<4;k=k+1)begin db[k]<=0;hold[k]<=0;end
 end else begin
  meta<=key_n;sync<=meta;short_key<=0;long_key<=0;press_key<=0;old_key_scene<=key_scene;
  for(k=0;k<4;k=k+1)begin
   if(key_scene!=old_key_scene)begin blocked[k]<=1;fired[k]<=1;hold[k]<=0;end
   else if(stable[k] && sync[k])begin blocked[k]<=0;hold[k]<=0;fired[k]<=0;end
   if(sync[k]==stable[k])db[k]<=0;
   else if(key_tick && db[k]==DB_TICKS-1)begin
    db[k]<=0;stable[k]<=sync[k];
    if(!sync[k] && !blocked[k] && key_scene==old_key_scene)press_key[k]<=1;
    if(sync[k])begin
     if(!fired[k] && !blocked[k] && key_scene==old_key_scene)short_key[k]<=1;
     hold[k]<=0;
    end
   end else if(key_tick)db[k]<=db[k]+1'b1;
   if(key_tick && !stable[k] && !blocked[k] && !fired[k] && key_scene==old_key_scene)begin
    if(hold[k]==HOLD_TICKS-1)begin fired[k]<=1;long_key[k]<=1;end
    else hold[k]<=hold[k]+1'b1;
   end
  end
 end
end
endmodule
