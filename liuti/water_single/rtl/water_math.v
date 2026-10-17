// Streaming fixed-point geometry. No prerecorded animation frames.
module water_sqrt #(parameter DW=46)(input clk,rst,valid,input[23:0] rad,input[DW-1:0] data,
 output out_valid,output[11:0] root,output[DW-1:0] out_data);
wire[23:0] a[0:12];wire[25:0] rem[0:12];wire[11:0] q[0:12];
wire[DW-1:0] d[0:12];wire[12:0] v;
assign a[0]=rad;assign rem[0]=0;assign q[0]=0;assign d[0]=data;assign v[0]=valid;
genvar i;generate for(i=0;i<12;i=i+1)begin:g
 wire[25:0] shifted=(rem[i]<<2)|a[i][23:22];
 wire[25:0] trial=({14'd0,q[i]}<<2)|26'd1;
 // The subtraction sign also supplies the comparison; do not build two carry chains.
 wire[26:0] difference={1'b0,shifted}-{1'b0,trial};
 reg[23:0] ar;reg[25:0] rr;reg[11:0] qr;reg[DW-1:0] dr;reg vr;
 always @(posedge clk)begin
  ar<=a[i]<<2;rr<=difference[26] ? shifted:difference[25:0];
  qr<=(q[i]<<1)|(!difference[26]);dr<=d[i];vr<=v[i]&&!rst;
 end
 assign a[i+1]=ar;assign rem[i+1]=rr;assign q[i+1]=qr;assign d[i+1]=dr;assign v[i+1]=vr;
end endgenerate
assign root=q[12];assign out_data=d[12];assign out_valid=v[12];
endmodule

// Controls are latched for a complete reader frame. source selects one of two
// drops, while its one-bit tag follows the coordinates through the pipeline.
// One vector per clock permits two drops per coordinate in alternating cycles.
module water_drop_vector(input clk,rst,valid,input[9:0] xword,y,input source,
 input enabled0,enabled1,water_mode,input[8:0] progress,
 input[10:0] cx0,cx1,input[9:0] cy0,cy1,input[11:0] radius0,radius1,
 output reg out_valid,output reg signed[12:0] delta_x,delta_y,
 output reg[9:0] out_xword,out_y,output reg out_source);
wire[10:0] cx=source ? cx1:cx0;
wire[9:0] cy=source ? cy1:cy0;
wire signed[12:0] dx=$signed({2'b0,xword,1'b0})-$signed({2'b0,cx});
wire signed[12:0] dy=$signed({3'b0,y})-$signed({3'b0,cy});
wire signed[16:0] scaled_x=($signed(dx)<<<3)+$signed(dx);
wire signed[12:0] rx=(water_mode&&!source) ? scaled_x>>>4:dx;
// Both consecutive drop vectors use the same coordinate. Retain it once in
// a 16-entry LUT-RAM queue instead of shifting 20 bits through every sqrt stage.
// Only the one-bit drop tag follows the arithmetic pipeline.
reg[3:0] coord_write,coord_read;
wire[19:0] coordinates;
wire coordinate_push=valid&&!source&&!rst;
wire coordinate_pop;
always @(posedge clk)begin
 if(rst)begin coord_write<=0;coord_read<=0;end
 else begin
  if(coordinate_push)coord_write<=coord_write+1'b1;
  if(coordinate_pop)coord_read<=coord_read+1'b1;
 end
end
`ifdef WATER_SIM
reg[19:0] coordinate_memory[0:15];reg[4:0] coordinate_count=0;
always @(posedge clk)begin
 if(coordinate_push)coordinate_memory[coord_write]<={xword,y};
 if(rst)coordinate_count<=0;
 else begin
  case({coordinate_push,coordinate_pop})2'b10:coordinate_count<=coordinate_count+1'b1;2'b01:coordinate_count<=coordinate_count-1'b1;endcase
  if(coordinate_push&&!coordinate_pop&&coordinate_count==16)$fatal(1,"coordinate token FIFO overflow");
  if(coordinate_pop&&coordinate_count==0)$fatal(1,"coordinate token FIFO underflow");
 end
end
assign coordinates=coordinate_memory[coord_read];
`else
EG_LOGIC_DRAM #(.DATA_WIDTH_W(20),.DATA_WIDTH_R(20),.ADDR_WIDTH_W(4),.ADDR_WIDTH_R(4),
 .DATA_DEPTH_W(16),.DATA_DEPTH_R(16)) coordinate_memory(
 .di({xword,y}),.waddr(coord_write),.we(coordinate_push),.wclk(clk),.raddr(coord_read),.do(coordinates));
`endif
// |dx| <= 2047 and |dy| <= 1023 even at the full port range. No
// truncation of valid coordinates: all eleven magnitude bits are retained.
// Exact unsigned square: one diagonal bit and one doubled cross term
// for each unique bit pair. A carry-save tree leaves only one carry-propagate sum.
function[25:0] exact_square;input signed[12:0] v;reg[10:0] b;
reg s0,c0,s1,c1,s2,c2,s3,c3,s4,c4,s5,c5,s6,c6,s7,c7,s8,c8,s9,c9,s10,c10,s11,c11,s12,c12,s13,c13,s14,c14,s15,c15,s16,c16,s17,c17,s18,c18,s19,c19,s20,c20,s21,c21,s22,c22,s23,c23,s24,c24,s25,c25,s26,c26,s27,c27,s28,c28,s29,c29,s30,c30,s31,c31,s32,c32,s33,c33,s34,c34,s35,c35;begin
 b=v<0 ? -v:v;
 s0=b[2]^(b[2] & b[1])^(b[3] & b[0]);c0=(b[2]&(b[2] & b[1]))|(b[2]&(b[3] & b[0]))|((b[2] & b[1])&(b[3] & b[0]));
 s1=b[3]^(b[3] & b[2])^(b[4] & b[1]);c1=(b[3]&(b[3] & b[2]))|(b[3]&(b[4] & b[1]))|((b[3] & b[2])&(b[4] & b[1]));
 s2=(b[4] & b[2])^(b[5] & b[1])^(b[6] & b[0]);c2=((b[4] & b[2])&(b[5] & b[1]))|((b[4] & b[2])&(b[6] & b[0]))|((b[5] & b[1])&(b[6] & b[0]));
 s3=b[4]^(b[4] & b[3])^(b[5] & b[2]);c3=(b[4]&(b[4] & b[3]))|(b[4]&(b[5] & b[2]))|((b[4] & b[3])&(b[5] & b[2]));
 s4=(b[5] & b[3])^(b[6] & b[2])^(b[7] & b[1]);c4=((b[5] & b[3])&(b[6] & b[2]))|((b[5] & b[3])&(b[7] & b[1]))|((b[6] & b[2])&(b[7] & b[1]));
 s5=b[5]^(b[5] & b[4])^(b[6] & b[3]);c5=(b[5]&(b[5] & b[4]))|(b[5]&(b[6] & b[3]))|((b[5] & b[4])&(b[6] & b[3]));
 s6=(b[7] & b[2])^(b[8] & b[1])^(b[9] & b[0]);c6=((b[7] & b[2])&(b[8] & b[1]))|((b[7] & b[2])&(b[9] & b[0]))|((b[8] & b[1])&(b[9] & b[0]));
 s7=(b[6] & b[4])^(b[7] & b[3])^(b[8] & b[2]);c7=((b[6] & b[4])&(b[7] & b[3]))|((b[6] & b[4])&(b[8] & b[2]))|((b[7] & b[3])&(b[8] & b[2]));
 s8=b[6]^(b[6] & b[5])^(b[7] & b[4]);c8=(b[6]&(b[6] & b[5]))|(b[6]&(b[7] & b[4]))|((b[6] & b[5])&(b[7] & b[4]));
 s9=(b[8] & b[3])^(b[9] & b[2])^(b[10] & b[1]);c9=((b[8] & b[3])&(b[9] & b[2]))|((b[8] & b[3])&(b[10] & b[1]))|((b[9] & b[2])&(b[10] & b[1]));
 s10=(b[7] & b[5])^(b[8] & b[4])^(b[9] & b[3]);c10=((b[7] & b[5])&(b[8] & b[4]))|((b[7] & b[5])&(b[9] & b[3]))|((b[8] & b[4])&(b[9] & b[3]));
 s11=b[7]^(b[7] & b[6])^(b[8] & b[5]);c11=(b[7]&(b[7] & b[6]))|(b[7]&(b[8] & b[5]))|((b[7] & b[6])&(b[8] & b[5]));
 s12=(b[8] & b[6])^(b[9] & b[5])^(b[10] & b[4]);c12=((b[8] & b[6])&(b[9] & b[5]))|((b[8] & b[6])&(b[10] & b[4]))|((b[9] & b[5])&(b[10] & b[4]));
 s13=b[8]^(b[8] & b[7])^(b[9] & b[6]);c13=(b[8]&(b[8] & b[7]))|(b[8]&(b[9] & b[6]))|((b[8] & b[7])&(b[9] & b[6]));
 s14=b[9]^(b[9] & b[8])^(b[10] & b[7]);c14=(b[9]&(b[9] & b[8]))|(b[9]&(b[10] & b[7]))|((b[9] & b[8])&(b[10] & b[7]));
 s15=c0^(b[3] & b[1])^(b[4] & b[0]);c15=(c0&(b[3] & b[1]))|(c0&(b[4] & b[0]))|((b[3] & b[1])&(b[4] & b[0]));
 s16=c2^s3^(b[6] & b[1]);c16=(c2&s3)|(c2&(b[6] & b[1]))|(s3&(b[6] & b[1]));
 s17=c3^s4^(b[8] & b[0]);c17=(c3&s4)|(c3&(b[8] & b[0]))|(s4&(b[8] & b[0]));
 s18=c4^s5^s6;c18=(c4&s5)|(c4&s6)|(s5&s6);
 s19=c5^c6^s7;c19=(c5&c6)|(c5&s7)|(c6&s7);
 s20=c7^s8^s9;c20=(c7&s8)|(c7&s9)|(s8&s9);
 s21=c8^c9^s10;c21=(c8&c9)|(c8&s10)|(c9&s10);
 s22=c10^s11^(b[9] & b[4]);c22=(c10&s11)|(c10&(b[9] & b[4]))|(s11&(b[9] & b[4]));
 s23=c12^s13^(b[10] & b[5]);c23=(c12&s13)|(c12&(b[10] & b[5]))|(s13&(b[10] & b[5]));
 s24=c13^(b[9] & b[7])^(b[10] & b[6]);c24=(c13&(b[9] & b[7]))|(c13&(b[10] & b[6]))|((b[9] & b[7])&(b[10] & b[6]));
 s25=c15^s1^(b[5] & b[0]);c25=(c15&s1)|(c15&(b[5] & b[0]))|(s1&(b[5] & b[0]));
 s26=c18^s19^(b[9] & b[1]);c26=(c18&s19)|(c18&(b[9] & b[1]))|(s19&(b[9] & b[1]));
 s27=c20^s21^(b[10] & b[2]);c27=(c20&s21)|(c20&(b[10] & b[2]))|(s21&(b[10] & b[2]));
 s28=c21^s22^(b[10] & b[3]);c28=(c21&s22)|(c21&(b[10] & b[3]))|(s22&(b[10] & b[3]));
 s29=c22^c11^s12;c29=(c22&c11)|(c22&s12)|(c11&s12);
 s30=c25^c1^s2;c30=(c25&c1)|(c25&s2)|(c1&s2);
 s31=c26^c19^s20;c31=(c26&c19)|(c26&s20)|(c19&s20);
 s32=c30^s16^(b[7] & b[0]);c32=(c30&s16)|(c30&(b[7] & b[0]))|(s16&(b[7] & b[0]));
 s33=c32^c16^s17;c33=(c32&c16)|(c32&s17)|(c16&s17);
 s34=c33^c17^s18;c34=(c33&c17)|(c33&s18)|(c17&s18);
 s35=c34^s26^(b[10] & b[0]);c35=(c34&s26)|(c34&(b[10] & b[0]))|(s26&(b[10] & b[0]));
 exact_square={4'd0,{1'b0,b[10],c14,c24,c23,c29,c28,c27,c31,c35,s35,s34,s33,s32,s30,s25,s15,s0,(b[2] & b[0]),b[1],1'b0,b[0]}}+{4'd0,{1'b0,(b[10] & b[9]),(b[10] & b[8]),s14,s24,s23,s29,s28,s27,s31,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,(b[1] & b[0]),1'b0,1'b0}};
end endfunction
reg[25:0] square_x,square_y;reg m0,m1;reg v0,v1;reg[23:0] rad;
always @(posedge clk)begin
 square_x<=exact_square(rx);square_y<=exact_square(dy);m0<=source;v0<=valid&&!rst;
 rad<=square_x+square_y;m1<=m0;v1<=v0&&!rst;
end
wire[11:0] distance;wire meta;wire sqrt_valid;
water_sqrt #(.DW(1)) sq(.clk(clk),.rst(rst),.valid(v1),.rad(rad),.data(m1),.out_valid(sqrt_valid),.root(distance),.out_data(meta));
reg signed[15:0] wave[0:255];reg[16:0] inverse[0:2047];reg signed[15:0] sine[0:511];
initial begin $readmemh("water_wave.hex",wave);$readmemh("water_inverse.hex",inverse);$readmemh("water_sine.hex",sine);end
wire[11:0] radius=meta ? radius1:radius0;
wire enabled=meta ? enabled1:enabled0;
wire signed[13:0] dr=$signed({2'b0,distance})-$signed({2'b0,radius});
wire[23:0] phase_r=({12'd0,distance}<<9)+({12'd0,distance}<<8)+({12'd0,distance}<<6)+({12'd0,distance}<<5)+({12'd0,distance}<<2)+distance;
wire[23:0] phase_p=({15'd0,progress}<<11)+({15'd0,progress}<<8)+({15'd0,progress}<<7)+({15'd0,progress}<<3)+({15'd0,progress}<<2)+progress;
wire[8:0] sine_address=(phase_r>>8)-(phase_p>>8);
wire[18:0] water_limit=({10'd0,progress}<<9)+({10'd0,progress}<<7)+({10'd0,progress}<<6)+({10'd0,progress}<<4);
reg signed[15:0] profile,sin_q;reg[16:0] inv;reg inside_water,enabled_q;reg m2,m3,m4;reg[20:0] m5;
reg v2,v3,v4,v5;reg signed[33:0] product;reg signed[15:0] gain;
// Normalize displacement by distance; the old sine gain stretched by radius.
wire signed[15:0] water_profile=inside_water ? sin_q-(sin_q>>>2):16'sd0;
wire signed[15:0] selected_profile=(water_mode&&!m2) ? water_profile:profile;
reg signed[28:0] px,py;
assign coordinate_pop=v4&&m4&&!rst;
wire[10:0] mcx=m4 ? cx1:cx0;
wire[9:0] mcy=m4 ? cy1:cy0;
wire signed[12:0] mx=$signed({2'b0,coordinates[19:10],1'b0})-$signed({2'b0,mcx});
wire signed[12:0] my=$signed({3'b0,coordinates[9:0]})-$signed({3'b0,mcy});
always @(posedge clk)begin
 profile<=enabled && dr>=-96 && dr<=96 ? wave[dr+96]:16'sd0;
 inv<=distance<2048 ? inverse[distance[10:0]]:17'd0;
 sin_q<=sine[sine_address];inside_water<=(distance<<8)<=water_limit;enabled_q<=enabled;
 m2<=meta;v2<=sqrt_valid&&!rst;
 product<=selected_profile*$signed({1'b0,inv});m3<=m2;v3<=v2&&!rst;
 gain<=product>>>12;m4<=m3;v4<=v3&&!rst;
 px<=mx*gain;py<=my*gain;m5<={m4,coordinates};v5<=v4&&!rst;
 delta_x<=px>>>12;delta_y<=py>>>12;out_xword<=m5[19:10];out_y<=m5[9:0];out_source<=m5[20];out_valid<=v5&&!rst;
end
endmodule

// Accept at most one coordinate every two clocks, matching the worst-case
// dual-image SDRAM cadence. A single geometry engine computes drop 0 then 1.
// No derived clocks, DSP overclocking, or extra external-memory traffic.
module water_warp(input clk,rst,valid,input[9:0] xword,y,input water_mode,input[8:0] progress,
 input drop0,drop1,input[10:0] cx0,cx1,input[9:0] cy0,cy1,input[11:0] radius0,radius1,
 output reg out_valid,output reg[9:0] sxword,sy,out_xword,out_y);
reg pending;reg[9:0] saved_x,saved_y;
always @(posedge clk)begin
 pending<=valid&&!rst;
 if(valid)begin saved_x<=xword;saved_y<=y;end
end
wire v,source;wire signed[12:0] dx,dy;wire[9:0] ox,oy;
water_drop_vector engine(.clk(clk),.rst(rst),.valid(valid||pending),
 .xword(pending ? saved_x:xword),.y(pending ? saved_y:y),.source(pending),
 .enabled0(water_mode||drop0),.enabled1(drop1&&!water_mode),
 .water_mode(water_mode),.progress(progress),
 .cx0(water_mode ? 11'd640:cx0),.cy0(water_mode ? 10'd360:cy0),
 .cx1(cx1),.cy1(cy1),.radius0(radius0),.radius1(radius1),
 .out_valid(v),.delta_x(dx),.delta_y(dy),.out_xword(ox),.out_y(oy),.out_source(source));
reg signed[12:0] dx0,dy0;
wire signed[14:0] tx=$signed({4'd0,ox,1'b0})+$signed(dx0)+$signed(dx);
wire signed[13:0] sum_y=$signed(dy0)+$signed(dy);
// Keep both overlapping drops within the rolling cache's fourteen-row halo.
wire signed[13:0] limited_y=sum_y < -14 ? -14:sum_y > 14 ? 14:sum_y;
wire signed[14:0] ty=$signed({5'd0,oy})+$signed(limited_y);
always @(posedge clk)begin
 if(v&&!source)begin dx0<=dx;dy0<=dy;end
 out_valid<=v&&source&&!rst;out_xword<=ox;out_y<=oy;
 sxword<=tx<0 ? 10'd0:tx>1278 ? 10'd639:tx[10:1];
 sy<=ty<0 ? 10'd0:ty>719 ? 10'd719:ty[9:0];
end
endmodule
