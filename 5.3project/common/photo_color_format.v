`timescale 1ns/1ps
// RGB565 only: two pixels per SDRAM word, most significant pixel first.
module photo_color_pack(
 input clk,rst,clear,valid,input [23:0] rgb,
 output reg word_valid,output reg [31:0] word_data,output aligned
);
reg phase;reg [15:0] saved;
wire [15:0] pixel565={rgb[23:19],rgb[15:10],rgb[7:3]};
assign aligned=!phase;
always @(posedge clk or posedge rst)begin
 if(rst)begin phase<=0;saved<=0;word_valid<=0;word_data<=0;end
 else begin
  word_valid<=0;
  if(clear)begin phase<=0;saved<=0;end
  else if(valid)begin
   phase<=!phase;
   if(!phase)saved<=pixel565;
   else begin word_data<={saved,pixel565};word_valid<=1;end
  end
 end
end
endmodule
