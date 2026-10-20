// RGB565 pair interpolation, alpha 0..256. SDRAM returns two reads per
// blended word, so valid is separated by at least one clock. Use that clock
// for the second pixel, reusing three channel multipliers without throttling
// the reader. Output latency is four edges including the accepting edge.
module water_blend(input clk,rst,valid,input[31:0] old_word,new_word,input[8:0] alpha,
 output reg out_valid,output reg[31:0] word_out);
// Exact small signed-by-alpha product. A balanced shift/add tree uses LUT
// carry chains instead of one DSP for each 5/6-bit RGB565 colour channel.
// Radix-four Booth recoding of the seven-bit signed difference gives four
// partial products. Negative-row corrections share one carry-save reduction.
function signed[16:0] alpha_product;
 input signed[6:0] d;input[8:0] w;
 reg[2:0] code0,code1,code2,code3;
 reg[10:0] mag0,mag1,mag2,mag3;
 reg[16:0] p0,p1,p2,p3,correction,s0,c0,s1,c1,s2,c2;
 begin
 code0={d[1:0],1'b0};code1=d[3:1];code2=d[5:3];code3={d[6],d[6:5]};
 mag0=code0[0]^code0[1] ? {2'd0,w}:
  ((code0==3'b011)||(code0==3'b100)) ? {1'b0,w,1'b0}:11'd0;
 p0={{6{code0[2]}},(mag0^{11{code0[2]}})} << 0;
 mag1=code1[0]^code1[1] ? {2'd0,w}:
  ((code1==3'b011)||(code1==3'b100)) ? {1'b0,w,1'b0}:11'd0;
 p1={{6{code1[2]}},(mag1^{11{code1[2]}})} << 2;
 mag2=code2[0]^code2[1] ? {2'd0,w}:
  ((code2==3'b011)||(code2==3'b100)) ? {1'b0,w,1'b0}:11'd0;
 p2={{6{code2[2]}},(mag2^{11{code2[2]}})} << 4;
 mag3=code3[0]^code3[1] ? {2'd0,w}:
  ((code3==3'b011)||(code3==3'b100)) ? {1'b0,w,1'b0}:11'd0;
 p3={{6{code3[2]}},(mag3^{11{code3[2]}})} << 6;
 correction={10'd0,code3[2],1'b0,code2[2],1'b0,code1[2],1'b0,code0[2]};
 s0=p0^p1^p2;c0=((p0&p1)|(p0&p2)|(p1&p2))<<1;
 s1=s0^c0^p3;c1=((s0&c0)|(s0&p3)|(c0&p3))<<1;
 s2=s1^c1^correction;c2=((s1&c1)|(s1&correction)|(c1&correction))<<1;
 alpha_product=s2+c2;
 end
endfunction
reg pending;reg[15:0] old_low,new_low;reg[8:0] alpha_low;
wire[15:0] a=valid ? old_word[31:16]:old_low;
wire[15:0] b=valid ? new_word[31:16]:new_low;
wire[8:0] selected_alpha=valid ? alpha:alpha_low;
wire[5:0] ac[0:2],bc[0:2];
assign ac[0]={1'b0,a[15:11]};assign ac[1]=a[10:5];assign ac[2]={1'b0,a[4:0]};
assign bc[0]={1'b0,b[15:11]};assign bc[1]=b[10:5];assign bc[2]={1'b0,b[4:0]};
reg v0,v1,low0,low1;reg[8:0] aq;reg[15:0] upper;
wire signed[17:0] sum[0:2];genvar g;generate for(g=0;g<3;g=g+1)begin:s
 // Scalar registers prevent tiny channel arrays becoming dedicated BRAMs.
 reg signed[6:0] diff;reg[5:0] old,old2;reg signed[16:0] prod;
 always @(posedge clk)begin
  old<=ac[g];diff<=$signed({1'b0,bc[g]})-$signed({1'b0,ac[g]});
  prod<=alpha_product(diff,aq);old2<=old;
 end
 assign sum[g]=$signed({4'd0,old2,8'd0})+$signed(prod)+18'sd128;
end endgenerate
always @(posedge clk)begin
 pending<=valid&&!rst;
 if(valid)begin old_low<=old_word[15:0];new_low<=new_word[15:0];alpha_low<=alpha;end
 aq<=selected_alpha;v0<=(valid||pending)&&!rst;low0<=!valid;
 v1<=v0&&!rst;low1<=low0;out_valid<=v1&&low1&&!rst;
 if(v1&&!low1)upper<={sum[0][12:8],sum[1][13:8],sum[2][12:8]};
 if(v1&&low1)word_out<={upper,sum[0][12:8],sum[1][13:8],sum[2][12:8]};
end
endmodule
