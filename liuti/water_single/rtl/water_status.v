// Six hex digits: decoder state, BMP count, AUD count, retained error,
// read timeout low nibble, {SDRAM initialized, HDMI locked, underrun, overflow}.
module water_status(input clk,rst,input[3:0] state,input[2:0] images,audio,error_code,
 input[7:0] asynchronous_status,output reg[5:0] seg_sel,output reg[7:0] seg_data);
(* async_reg="true" *)reg[7:0] meta,sync;
reg[2:0] last_error;reg[15:0] timer;reg[2:0] digit;
reg[3:0] value;
function[7:0] glyph;input[3:0] n;begin case(n)
 0:glyph=8'hc0;1:glyph=8'hf9;2:glyph=8'ha4;3:glyph=8'hb0;
 4:glyph=8'h99;5:glyph=8'h92;6:glyph=8'h82;7:glyph=8'hf8;
 8:glyph=8'h80;9:glyph=8'h90;10:glyph=8'h88;11:glyph=8'h83;
 12:glyph=8'hc6;13:glyph=8'ha1;14:glyph=8'h86;default:glyph=8'h8e;
endcase end endfunction
always @* begin case(digit)
 5:value=state;4:value={1'b0,images};3:value={1'b0,audio};
 2:value={1'b0,last_error};1:value=sync[3:0];default:value=sync[7:4];
endcase end
always @(posedge clk)begin
 if(rst)begin meta<=0;sync<=0;last_error<=0;timer<=0;digit<=0;seg_sel<=6'b111111;seg_data<=8'hff;end
 else begin
  meta<=asynchronous_status;sync<=meta;
  if(error_code!=0)last_error<=error_code;
  if(timer==49999)begin timer<=0;digit<=digit==5 ? 0:digit+1'b1;end else timer<=timer+1'b1;
  seg_sel<=~(6'b000001<<digit);seg_data<=glyph(value);
 end
end
endmodule
