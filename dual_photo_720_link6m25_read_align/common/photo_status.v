`timescale 1ns/1ps
// Rightmost digit keeps the original status. Left to right: N I E TT S.
module photo_status #(parameter CLK_HZ=50000000)(
 input clk,rst,input [3:0] status,error,state,input [2:0] image,count,
 input [2:0] diagnostic_page,input [15:0] diagnostic_crc,
 output reg [5:0] seg_sel,output reg [7:0] seg_data);
localparam DIV=CLK_HZ/6000;
reg [31:0] ticks;reg [2:0] index;reg [23:0] digits;reg [3:0] digit;
function [7:0] glyph;
 input [3:0] v;
 begin case(v)
 0:glyph='hc0;1:glyph='hf9;2:glyph='ha4;3:glyph='hb0;4:glyph='h99;
 5:glyph='h92;6:glyph='h82;7:glyph='hf8;8:glyph='h80;9:glyph='h90;
 10:glyph='h88;11:glyph='h83;12:glyph='hc6;13:glyph='ha1;14:glyph='h86;default:glyph='h8e;
 endcase end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin ticks<=0;index<=0;digits<=0;end
 else if(ticks==DIV-1)begin
  ticks<=0;index<=index==5 ? 0:index+1'b1;
  if(index==5)begin
   case(diagnostic_page)
    // User reads digit indices 0..5: page, four hex digits (MSB first), C.
    1,2,3,4:digits<={4'hc,diagnostic_crc[3:0],diagnostic_crc[7:4],diagnostic_crc[11:8],diagnostic_crc[15:12],1'b0,diagnostic_page};
    default:digits<={1'b0,count,1'b0,image,error,(state>=10 ? 4'd1:4'd0),(state>=10 ? state-4'd10:state),status};
   endcase
  end
 end else ticks<=ticks+1'b1;
end
always @*begin
 digit=(digits>>(index*4));seg_data=glyph(digit);seg_sel=6'b111111 ^ (6'b000001<<index);
end
endmodule
