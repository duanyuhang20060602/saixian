// Cut the long audio-control -> visualization reset route in the pixel domain.
// Global reset stays asynchronous; stream/scene resets are sampled for one clock.
module photo_visual_reset(input clk,rst,stream_reset,owner_change,output reg reset);
always @(posedge clk or posedge rst)
 if(rst)reset<=1'b1;
 else reset<=stream_reset || owner_change;
endmodule
