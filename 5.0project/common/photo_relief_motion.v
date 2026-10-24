// Frame-boundary controls for the golden relief player. Rotation is enabled
// immediately on entry. Pause freezes angle and automatic light together.
module photo_relief_motion #(parameter HOLD_FRAMES=15)(
 input clk,rst,enable,pause,frame_tick,
 input touch_contact,input [10:0] cursor_x,input [9:0] cursor_y,
 output reg [4:0] angle,
 output reg signed [5:0] light_x,light_y,
 output reg frame_update
);
reg [7:0] hold_count;
reg [6:0] phase;
wire signed [6:0] pointer_x=$signed({2'b00,cursor_x[10:5]})-7'sd20;
wire signed [6:0] pointer_y=7'sd11-$signed({2'b00,cursor_y[9:5]});
wire signed [5:0] sweep=phase[6] ? 6'sd15-$signed({1'b0,phase[5:1]}):
 $signed({1'b0,phase[5:1]})-6'sd16;
always @(posedge clk)begin
 if(rst || !enable)begin
  angle<=0;hold_count<=0;phase<=0;light_x<=-16;light_y<=6;frame_update<=0;
 end else begin
  frame_update<=0;
  if(frame_tick)begin
   frame_update<=1;
   if(!pause)begin
    phase<=phase+1'b1;
    if(hold_count==HOLD_FRAMES-1)begin
     hold_count<=0;angle<=angle==23 ? 5'd0:angle+1'b1;
    end else hold_count<=hold_count+1'b1;
    if(!touch_contact)begin light_x<=sweep;light_y<=6;end
   end
   if(touch_contact)begin
    light_x<=pointer_x< -24 ? -6'sd24:pointer_x>24 ? 6'sd24:pointer_x[5:0];
    light_y<=pointer_y< -16 ? -6'sd16:pointer_y>16 ? 6'sd16:pointer_y[5:0];
   end
  end
 end
end
endmodule
