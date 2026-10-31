// Align the four-clock scoreboard to the established 34-clock scene.
// Scene selection changes only when the output raster reaches vertical blank.
module photo_match_video(input clk,rst,active,input[11:0] x34,input[10:0] y34,input valid34,
 input[23:0] rgb_in,input de_in,output[23:0] rgb_out,output de_out,
 input[2:0] state,team_a,team_b,input[9:0] score_a,score_b,input[8:0] seconds,
 input[1:0] duration_index,countdown);
wire[11:0] x30;wire[10:0] y30;wire valid30;
photo_raster_delay #(.DELAY(30)) raster(.clk(clk),.rst(rst),.x(x30),.y(y30),.valid(valid30));
wire tick30=valid30 && x30==0 && y30==720;
wire[23:0] match_rgb;wire match_de;
reg display;
always @(posedge clk or posedge rst)
 if(rst)display<=0;else if(valid34 && x34==0 && y34==720)display<=active;
photo_match_render render(.clk(clk),.rst(rst),.frame_tick(tick30),
 .x(x30[10:0]),.y(y30[9:0]),.de(valid30 && x30<1280 && y30<720),
 .vs(valid30 && y30>=725 && y30<730),
 .state(state),.team_a(team_a),.team_b(team_b),.score_a(score_a),.score_b(score_b),
 .remaining(seconds),.duration_index(duration_index),.countdown(countdown),
 .rgb(match_rgb),.out_de(match_de),.out_vs());
assign rgb_out=display ? match_rgb:rgb_in;
assign de_out=display ? match_de:de_in;
endmodule
