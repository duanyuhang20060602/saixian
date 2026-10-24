`timescale 1ns/1ps
// Streaming RGB888 packing: four pixels become three 32-bit words.
// W0={P0,R1}, W1={G1,B1,R2,G2}, W2={B2,P3}, MSB first.
// RGB565 retains the original high/low two-pixel order. No RAM is used.
module photo_color_pack_frozen(
 input clk,rst,clear,high_color,valid,input [23:0] rgb,
 output reg word_valid,output reg [31:0] word_data,output aligned
);
reg [1:0] phase;
reg [23:0] saved;
wire [15:0] pixel565={rgb[23:19],rgb[15:10],rgb[7:3]};
assign aligned=phase==0;
always @(posedge clk or posedge rst)begin
 if(rst)begin phase<=0;saved<=0;word_valid<=0;word_data<=0;end
 else begin
  word_valid<=0;
  if(clear)begin phase<=0;saved<=0;end
  else if(valid)begin
   if(high_color)begin
    phase<=phase+1'b1;
    case(phase)
     0:saved<=rgb;
     1:begin word_data<={saved,rgb[23:16]};word_valid<=1;saved<={8'd0,rgb[15:0]};end
     2:begin word_data<={saved[15:0],rgb[23:8]};word_valid<=1;saved<={16'd0,rgb[7:0]};end
     3:begin word_data<={saved[7:0],rgb};word_valid<=1;end
    endcase
   end else begin
    phase<={1'b0,!phase[0]};
    if(!phase[0])saved<={8'd0,pixel565};
    else begin word_data<={saved[15:0],pixel565};word_valid<=1;end
   end
  end
 end
end
endmodule
