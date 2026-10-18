// One effect texel pair and four native pixels arrive every two clocks.
// Keep native samples outside displaced blocks. A one-block lookahead supplies
// the cross-word interpolation sample; the final block clamps within its row.
module water_reconstruct(input clk,rst,valid,last,affected,
 input[31:0] effect_word,input[63:0] native_pixels,
 output reg out_valid,output reg[31:0] word_out);
reg have,flush,low_pending,mask;reg[31:0] prev_effect,low_word;reg[63:0] prev_native;
function[15:0] average;input[15:0] a,b;reg[5:0] r,bl;reg[6:0] g;
 begin r={1'b0,a[15:11]}+{1'b0,b[15:11]}+1'b1;g={1'b0,a[10:5]}+{1'b0,b[10:5]}+1'b1;bl={1'b0,a[4:0]}+{1'b0,b[4:0]}+1'b1;
 average={r[5:1],g[6:1],bl[5:1]};end
endfunction
wire[15:0] a=prev_effect[31:16],b=prev_effect[15:0];
always @(posedge clk)begin
 if(rst)begin have<=0;flush<=0;low_pending<=0;mask<=0;prev_effect<=0;prev_native<=0;low_word<=0;out_valid<=0;word_out<=0;end
 else begin
  out_valid<=0;low_pending<=0;
  if(low_pending)begin out_valid<=1;word_out<=low_word;end
  if(valid)begin
   if(have)begin
    out_valid<=1;word_out<=mask ? {a,average(a,b)}:prev_native[63:32];
    low_word<=mask ? {b,average(b,effect_word[31:16])}:prev_native[31:0];low_pending<=1;
   end
   prev_effect<=effect_word;prev_native<=native_pixels;mask<=affected;have<=!last;
   if(last)flush<=1;
  end else if(flush&&!low_pending)begin
   out_valid<=1;word_out<=mask ? {a,average(a,b)}:prev_native[63:32];
   low_word<=mask ? {b,b}:prev_native[31:0];low_pending<=1;flush<=0;
  end
 end
end
endmodule
