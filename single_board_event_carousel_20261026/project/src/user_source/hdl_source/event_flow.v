`timescale 1ns/1ps
// The lobby, active match and award share one controller and one result record.
module event_flow #(parameter CLK_HZ=75000000,LOBBY_SECONDS=5,AWARD_SECONDS=12)(
 input clk,rst,input [3:0] short_key,long_key,
 output [2:0] state,team_a,team_b,output [9:0] score_a,score_b,
 output [8:0] remaining,output [1:0] duration_index,countdown,
 output [3:0] cue_event,output reg [1:0] page,
 output reg last_valid,output reg [2:0] last_a,last_b,
 output reg [9:0] last_score_a,last_score_b,output reg [6:0] last_number,
 output [6:0] next_number,output reg [6:0] active_number,output award_summary
);
reg lobby,start_pending,reset_pending;reg [3:0] forwarded_short,forwarded_long;
wire [2:0] match_state;reg [2:0] previous_match_state;
reg [26:0] count;reg [3:0] seconds;
assign state=lobby ? 3'd5:match_state;
assign next_number=last_valid ? (last_number==99 ? 7'd1:last_number+1'b1):7'd1;
assign award_summary=!lobby && match_state==4 && seconds>=8;
always @* begin
 forwarded_short=0;forwarded_long=0;
 if(!lobby)begin forwarded_short=short_key;forwarded_long=long_key;end
 if(match_state==4)forwarded_short=0;
 if(start_pending)forwarded_short=8;
 if(reset_pending)forwarded_short=8;
end
match_control #(.CLK_HZ(CLK_HZ)) match_core(.clk(clk),.rst(rst),.short_key(forwarded_short),.long_key(forwarded_long),
 .state(match_state),.team_a(team_a),.team_b(team_b),.score_a(score_a),.score_b(score_b),
 .remaining(remaining),.duration_index(duration_index),.countdown(countdown),.cue_event(cue_event));
always @(posedge clk or posedge rst)begin
 if(rst)begin lobby<=1;page<=0;last_valid<=0;last_a<=0;last_b<=1;last_score_a<=0;last_score_b<=0;
  last_number<=0;active_number<=1;previous_match_state<=0;count<=0;seconds<=0;start_pending<=0;reset_pending<=0;end
 else begin
  previous_match_state<=match_state;start_pending<=0;reset_pending<=0;
  if(match_state==1 && previous_match_state==0)active_number<=next_number;
  if(match_state==4 && previous_match_state!=4)begin
   last_valid<=1;last_a<=team_a;last_b<=team_b;last_score_a<=score_a;last_score_b<=score_b;
   last_number<=active_number;count<=0;seconds<=0;
  end
  if(lobby)begin
   if(count==CLK_HZ-1)begin
    count<=0;
    if(seconds==LOBBY_SECONDS-1)begin seconds<=0;page<=page+1'b1;end
    else seconds<=seconds+1'b1;
   end else count<=count+1'b1;
   if(short_key[0])begin page<=page-1'b1;count<=0;seconds<=0;end
   else if(short_key[1])begin page<=page+1'b1;count<=0;seconds<=0;end
   if(short_key[2] || short_key[3])begin
    lobby<=0;count<=0;seconds<=0;
    if(short_key[3] && !short_key[2])start_pending<=1;
   end
  end else if(match_state==4)begin
   if(previous_match_state==4)begin
    if(count==CLK_HZ-1)begin count<=0;seconds<=seconds+1'b1;end
    else count<=count+1'b1;
    if(short_key[3] || (count==CLK_HZ-1 && seconds==AWARD_SECONDS-1))begin
     lobby<=1;page<=3;count<=0;seconds<=0;reset_pending<=1;
    end
   end
  end else begin
   count<=0;seconds<=0;
   if(match_state==0 && long_key[3])begin lobby<=1;page<=1;end
  end
 end
end
endmodule
