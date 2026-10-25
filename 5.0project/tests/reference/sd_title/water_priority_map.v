`ifndef WATER_SIM
`ifndef FX11_NATIVE_DSP
`define FX11_NATIVE_DSP
`endif
`endif
`ifdef FX11_DSP_SIM
`ifndef FX11_NATIVE_DSP
`define FX11_NATIVE_DSP
`endif
`endif
`ifndef FX11_ROM_ROOT
`ifdef WATER_SIM
`define FX11_ROM_ROOT "common/fluid/"
`else
`define FX11_ROM_ROOT ""
`endif
`endif
// One projected coordinate arrives every two clocks. All eleven effects share
// one exact 17x17 multiplier: primary on the first slot, secondary on the next.
module water_effect_map_before(input clk,rst,valid,enabled,right,input[3:0] effect,
 input[8:0] progress,input[9:0] ox,oy,wx,wy,
 output out_valid,output[9:0] old_x,old_y,new_x,out_x,out_y,
 output[8:0] alpha,output[4:0] shade,output[2:0] shine);
wire bv,ev;wire[9:0] ba,by,bb,bx,bo,ea,ey,eb,ex,eo;
wire[8:0] bq,eq;wire[4:0] bs,es;wire[2:0] bh,eh;
wire extra_mode=effect==3||effect==4||effect==5||effect>=7;
reg[5:0] selection;
wire signed[16:0] extra_a,extra_b,extra_c,extra_d;
reg valid0,valid1,pending;
reg signed[16:0] second_a,second_b;
reg signed[33:0] shared_product,primary_product;
wire signed[16:0] operand_a=pending ? second_a:extra_a;
wire signed[16:0] operand_b=pending ? second_b:extra_b;
// Original input metadata is retained only until its last consumer. At a
// two-clock input interval, two token banks replace duplicate six-stage pipes.
wire[73:0] base_packet;wire[8:0] shared_t,shared_scale;wire signed[17:0] shared_bend;
wire iv,ie,ir;wire[3:0] fx;wire[8:0] ip;wire[9:0] ix,iy,iwx,iwy;
assign {iv,ie,ir,fx,ip,shared_t,shared_scale,ix,iy,iwx,iwy}=base_packet;
always @(posedge clk)begin
 selection<={selection[4:0],extra_mode};
 valid0<=valid&&!rst;valid1<=valid0&&!rst;
 pending<=valid1&&!rst;
 if(valid1)begin second_a<=extra_c;second_b<=extra_d;end
 shared_product<=operand_a*operand_b;primary_product<=shared_product;
 if(rst)begin pending<=0;valid0<=0;valid1<=0;selection<=0;end
end
`ifdef WATER_SIM
always @(posedge clk)if(!rst&&pending&&valid1)$fatal(1,"effect coordinate interval must be at least two clocks");
`endif
water_base_effect_map base(clk,rst,iv,ie,ir,fx[2:0],ip,ix,iy,iwx,iwy,bv,ba,by,bb,bx,bo,bq,bs,bh,primary_product,shared_t,shared_scale,shared_bend);
water_extra_effect_map_before extra(clk,rst,valid,enabled,right,effect,progress,ox,oy,wx,wy,
 ev,ea,ey,eb,ex,eo,eq,es,eh,primary_product,shared_product,extra_a,extra_b,extra_c,extra_d,base_packet,shared_bend);
assign {out_valid,old_x,old_y,new_x,out_x,out_y,alpha,shade,shine}=
 selection[5] ? {ev,ea,ey,eb,ex,eo,eq,es,eh}:{bv,ba,by,bb,bx,bo,bq,bs,bh};
endmodule

module water_extra_effect_map_before(input clk,rst,valid,enabled,right,input[3:0] effect,
 input[8:0] progress,input[9:0] ox,oy,wx,wy,
 output reg out_valid,output reg[9:0] old_x,old_y,new_x,out_x,out_y,
 output reg[8:0] alpha,output reg[4:0] shade,output reg[2:0] shine,
 input signed[33:0] product,second_product,output signed[16:0] multiply_a,multiply_b,multiply_c,multiply_d,
 output[73:0] base_packet,output signed[17:0] shared_bend);
reg signed[7:0] ribbon_shape[0:89];
initial $readmemh({`FX11_ROM_ROOT,"water_strip.hex"},ribbon_shape);
wire[10:0] px={ox,1'b0};wire[10:0] u=right ? 11'd1279-px:px;
wire signed[12:0] cx=$signed({2'd0,px})-13'sd640;
wire signed[11:0] cy=$signed({2'd0,oy})-12'sd360;
wire[8:0] envelope=progress<128 ? progress:9'd256-progress;
wire[5:0] wave_address=oy[5:0]+{oy[8:6],3'd0};
reg[2:0] column;reg[10:0] origin;reg signed[12:0] local_x;
reg[8:0] local_t,scale;reg signed[12:0] raw_t;
reg[1:0] glass_row,glass_col;reg[7:0] row_y;reg signed[12:0] tilted;
reg[6:0] ribbon_local_y;
reg[3:0] fragment_order;reg[2:0] ribbon_band,ribbon_order;
always @*begin
 // Balanced spatial partitions avoid a seven-way priority chain before
 // progress clipping and the synchronous reciprocal ROM address.
 if(u<640)begin
  if(u<320)begin
   if(u<160)begin column=0;origin=0;end else begin column=1;origin=160;end
  end else begin
   if(u<480)begin column=2;origin=320;end else begin column=3;origin=480;end
  end
 end else begin
  if(u<960)begin
   if(u<800)begin column=4;origin=640;end else begin column=5;origin=800;end
  end else begin
   if(u<1120)begin column=6;origin=960;end else begin column=7;origin=1120;end
  end
 end
 if(oy<360)begin
  if(oy<180)begin glass_row=0;row_y=oy;end else begin glass_row=1;row_y=oy-180;end
 end else begin
  if(oy<540)begin glass_row=2;row_y=oy-360;end else begin glass_row=3;row_y=oy-540;end
 end
 tilted=$signed({2'd0,u})+(($signed({5'd0,row_y})-13'sd90)>>>1);
 glass_col=tilted<320 ? 0:tilted<640 ? 1:tilted<960 ? 2:3;
 fragment_order=({2'd0,glass_col}+{1'b0,glass_col,1'b0})^({2'd0,glass_row}+{glass_row,2'd0});
 local_x=$signed({2'd0,u})-$signed({2'd0,origin})-13'sd80;
 if(oy<360)begin
  if(oy<180)begin
   if(oy<90)begin ribbon_band=0;ribbon_local_y=oy;end else begin ribbon_band=1;ribbon_local_y=oy-90;end
  end else begin
   if(oy<270)begin ribbon_band=2;ribbon_local_y=oy-180;end else begin ribbon_band=3;ribbon_local_y=oy-270;end
  end
 end else begin
  if(oy<540)begin
   if(oy<450)begin ribbon_band=4;ribbon_local_y=oy-360;end else begin ribbon_band=5;ribbon_local_y=oy-450;end
  end else begin
   if(oy<630)begin ribbon_band=6;ribbon_local_y=oy-540;end else begin ribbon_band=7;ribbon_local_y=oy-630;end
  end
 end
 ribbon_order={ribbon_band[0],ribbon_band[2:1]};
 raw_t=$signed({4'd0,progress});
 if(effect==2)raw_t=$signed({4'd0,progress})+$signed({6'd0,progress[8:2]})-$signed({7'd0,ribbon_order,3'd0});
 if(effect==3)raw_t=$signed({4'd0,progress})+$signed({5'd0,progress[8:1]})-$signed({6'd0,column,4'd0});
 if(effect==8)raw_t=($signed({4'd0,progress})<<<1)-$signed({5'd0,fragment_order,4'd0});
 local_t=raw_t<0 ? 0:raw_t>256 ? 256:raw_t[8:0];
 scale=local_t<128 ? 9'd256-(local_t<<1):(local_t<<1)-9'd256;
 if(effect==4||effect==9)scale=9'd256-progress;
end
// Six stages keep classification, reciprocal lookup, shared multiplication,
// geometry and final clipping separate. Two exact DSP operations share the
// two slots of each input block; latency is six clocks, throughput unchanged.
wire[150:0] packet={px,u,origin,ox,oy,wx,wy,progress,local_t,scale,envelope,
 local_x,tilted,ribbon_local_y,glass_col,effect,enabled,right,valid&&!rst};
reg[150:0] token0,token1;
reg write_slot,front_slot;reg[3:0] tags,tokens;
wire[150:0] packet_a=front_slot ? token1:token0;
wire[150:0] delayed_packet=tags[3] ? token1:token0;
// Capture the retiring bank before its next write. This is the same
// four-clock metadata boundary, with no bank mux on the geometry path.
wire[150:0] retiring_packet=tags[2] ? token1:token0;
reg[150:0] packet_c;
always @(posedge clk)begin
 if(rst)packet_c<=0;
 else packet_c<={retiring_packet[150:1],tokens[2]};
end
always @(posedge clk)begin
 tags<={tags[2:0],write_slot};tokens<={tokens[2:0],valid&&!rst};
 if(valid)begin
  if(write_slot)token1<=packet;else token0<=packet;
  front_slot<=write_slot;write_slot<=!write_slot;
 end
 if(rst)begin write_slot<=0;front_slot<=0;tags<=0;tokens<=0;end
end
// Unpack the packet rather than maintaining positional slices as modes grow.
wire[10:0] px_a,u_a,origin_a;wire[9:0] x_a,y_a,wx_a,wy_a;
wire[8:0] p_a,local_t_a,scale_a,env_a;wire signed[12:0] lx_a,tilt_a;
wire[6:0] ribbon_y_a;wire[1:0] gc_a;wire[3:0] fx_a;wire e_a,r_a,v_a;
assign {px_a,u_a,origin_a,x_a,y_a,wx_a,wy_a,p_a,local_t_a,scale_a,env_a,
 lx_a,tilt_a,ribbon_y_a,gc_a,fx_a,e_a,r_a,v_a}=packet_a;
wire signed[12:0] cx_a=$signed({2'd0,px_a})-13'sd640;
wire signed[11:0] cy_a=$signed({2'd0,y_a})-12'sd360;
wire[5:0] wave_index_a=y_a[5:0]+{y_a[8:6],3'd0};
// Quantized sine has exact quarter-wave symmetry: only seventeen
// distinct nonnegative magnitudes. Keep this small table in logic so the
// expanded reciprocal/progress-square ROM needs no additional RAM block.
function signed[6:0] wave_value;input[5:0] index;reg[4:0] quadrant;reg[5:0] amplitude;begin
 quadrant=index[4] ? 5'd16-{1'b0,index[3:0]}:{1'b0,index[3:0]};
 case(quadrant)
 0:amplitude=6'd0;
 1:amplitude=6'd3;
 2:amplitude=6'd6;
 3:amplitude=6'd9;
 4:amplitude=6'd12;
 5:amplitude=6'd15;
 6:amplitude=6'd18;
 7:amplitude=6'd20;
 8:amplitude=6'd23;
 9:amplitude=6'd25;
 10:amplitude=6'd27;
 11:amplitude=6'd28;
 12:amplitude=6'd30;
 13:amplitude=6'd31;
 14:amplitude=6'd31;
 15:amplitude=6'd32;
 16:amplitude=6'd32;
 default:amplitude=0;endcase
 wave_value=index[5] ? -$signed({1'b0,amplitude}):$signed({1'b0,amplitude});
end endfunction
wire signed[7:0] wave_a=wave_value(wave_index_a);
// Both primary and secondary operands feed the wrapper shared DSP.
// The same reciprocal ROM also supplies the original card-flip projection.
// The two slots of each coordinate also share one synchronous ROM read
// port: the primary coefficient first, then the tunnel's secondary coefficient.
// No asynchronous ROM fanout through the metadata token-bank multiplexer.
reg lookup_pending;reg[8:0] saved_progress;wire[15:0] lookup_value;
reg[3:0] operand_mode;
// Unused ROM addresses 257..511 hold p*p for 1..255. Endpoints
// 0 and 256 are explicit constants; reciprocal addresses 0..256 stay intact.
// Only flip, columns, accordion, portal and tunnel consume this ROM.
// Derive their addresses directly: glass/ribbon classification must not
// traverse a RAM setup path for a coefficient those effects never use.
wire[8:0] flip_lookup_t=progress>256 ? 9'd256:progress;
wire[8:0] flip_lookup_scale=flip_lookup_t<128 ? 9'd256-(flip_lookup_t<<1):(flip_lookup_t<<1)-9'd256;
wire signed[12:0] column_lookup_raw=$signed({4'd0,progress})+$signed({5'd0,progress[8:1]})-$signed({6'd0,column,4'd0});
wire[8:0] column_lookup_t=column_lookup_raw<0 ? 9'd0:column_lookup_raw>256 ? 9'd256:column_lookup_raw[8:0];
wire[8:0] column_lookup_scale=column_lookup_t<128 ? 9'd256-(column_lookup_t<<1):(column_lookup_t<<1)-9'd256;
wire[8:0] primary_index_now=effect==7 ? {1'b1,progress[7:0]}:
 effect==1 ? (flip_lookup_scale<16 ? 9'd16:flip_lookup_scale):
 effect==3 ? column_lookup_scale:(effect==4||effect==9) ? 9'd256-progress:9'd0;
water_effect_recip_rom_before coefficient(.clk(clk),
 .address(lookup_pending ? saved_progress:primary_index_now),.value(lookup_value));
always @(posedge clk)begin
 lookup_pending<=valid&&!rst;if(valid)saved_progress<=progress;
 operand_mode<=fx_a;
 if(rst)begin lookup_pending<=0;saved_progress<=0;operand_mode<=0;end
end
reg signed[16:0] ma,mb,na,nb,wa,wb;
reg signed[16:0] ma_b,mb_b,na_b,nb_b,wa_b,wb_b;
wire signed[15:0] small_wave_value;
water_wave_multiply_before small_wave(.a(wa_b[6:0]),.b(wb_b[7:0]),.value(small_wave_value));
always @*begin
 ma=$signed({8'd0,local_t_a});mb=ma;na=0;nb=0;
 wa=wave_a;wb=$signed({8'd0,env_a});
 case(fx_a)
  2:begin wa=ribbon_shape[ribbon_y_a];wb=local_t_a<=128 ? $signed({8'd0,local_t_a}):$signed(17'd256-{8'd0,local_t_a});end
  1:begin ma=cx_a;mb=$signed({1'b0,lookup_value});end
  3:begin ma=lx_a;mb=$signed({1'b0,lookup_value});end
  4:begin ma=$signed({6'd0,u_a});mb=$signed({1'b0,lookup_value});end
  7:begin ma=cx_a;mb=cx_a;na=cy_a;nb=cy_a;end
  9:begin ma=cx_a;mb=$signed({1'b0,lookup_value});na=cx_a;nb=0;end
 endcase
end
// The remaining product is only signed wave * unsigned envelope.
function signed[15:0] small_product; input signed[6:0] aa; input[7:0] b; reg signed[15:0] a; begin
a={{9{aa[6]}},aa};
small_product=((((b[0] ? ($signed(a) <<< 0) : 16'sd0)+(b[1] ? ($signed(a) <<< 1) : 16'sd0))+((b[2] ? ($signed(a) <<< 2) : 16'sd0)+(b[3] ? ($signed(a) <<< 3) : 16'sd0)))+(((b[4] ? ($signed(a) <<< 4) : 16'sd0)+(b[5] ? ($signed(a) <<< 5) : 16'sd0))+((b[6] ? ($signed(a) <<< 6) : 16'sd0)+(b[7] ? ($signed(a) <<< 7) : 16'sd0))));
end endfunction
reg[16:0] portal_square_b;
reg signed[19:0] wave_product0;reg signed[33:0] wave_product;
assign multiply_a=ma_b;assign multiply_b=mb_b;assign multiply_c=na_b;assign multiply_d=operand_mode==9 ? $signed({1'b0,lookup_value}):nb_b;
wire[10:0] px0,u0,origin0;wire[9:0] x0,y0,wx0,wy0;
wire[8:0] p0,t0,scale0,env0;wire signed[12:0] lx0,tilt0;
wire[6:0] ribbon_y0;wire[1:0] gc0;wire[3:0] fx0;wire e0,r0,v0;
assign {px0,u0,origin0,x0,y0,wx0,wy0,p0,t0,scale0,env0,
 lx0,tilt0,ribbon_y0,gc0,fx0,e0,r0,v0}=packet_c;
assign base_packet={v0,e0,r0,fx0,p0,t0,scale0,x0,y0,wx0,wy0};
assign shared_bend=wave_product[17:0];
always @(posedge clk)begin
 ma_b<=ma;mb_b<=mb;na_b<=na;nb_b<=nb;wa_b<=wa;wb_b<=wb;
 portal_square_b<=p_a==256 ? 17'd65536:p_a==0 ? 17'd0:{1'b0,lookup_value};
 wave_product0<=operand_mode==7 ? $signed({3'd0,portal_square_b}):small_wave_value;wave_product<=wave_product0;
end
// Only an old accordion pixel inside its compressed panel is shaded. Its
// projected source X is in 0..1279, so eight comparisons replace a 32-bit
// constant divider and its otherwise unnecessary DSP multipliers.
function[7:0] fold_phase;input[10:0] x;begin
 if(x<160)fold_phase=x;else if(x<320)fold_phase=x-160;
 else if(x<480)fold_phase=x-320;else if(x<640)fold_phase=x-480;
 else if(x<800)fold_phase=x-640;else if(x<960)fold_phase=x-800;
 else if(x<1120)fold_phase=x-960;else fold_phase=x-1120;
end endfunction
function[8:0] clipped_weight;input signed[21:0] n;begin clipped_weight=n<0 ? 0:n>256 ? 256:n[8:0];end endfunction
function[9:0] clipped_word;input signed[21:0] n;begin clipped_word=n<0 ? 0:n>1278 ? 639:n[10:1];end endfunction
function signed[21:0] magnitude;input signed[21:0] n;begin magnitude=n<0 ? -n:n;end endfunction
// Proven signed bounds: portal delta is in -539200..589824; projected X
// is at most 40928. Twenty-two bits preserve every valid result exactly.
// Constant-distance tests below compare both signed bounds in parallel.
// Valid geometry stays away from the signed minimum, so this is exactly
// abs(distance)<limit without a conditional negate on the highlight path.
// Separate coordinate, weight, shade and circular-distance ranges. Keeping
// every temporary at the 22-bit portal width duplicates long carry chains.
// Source coordinates retire modulo 2^17 at a_d/b_d, exactly as before.
reg signed[16:0] a,b;
reg signed[9:0] mix;
reg signed[6:0] darkness;
reg signed[3:0] glint;
reg signed[11:0] half_width,center;
reg signed[12:0] front,metric;
reg signed[13:0] distance;
reg signed[17:0] projection;
reg signed[10:0] travel;
reg signed[21:0] delta;
reg use_alpha;reg[8:0] bounded_alpha;reg[4:0] alpha_steps;
always @*begin
 a=px0;b=px0;mix=p0;darkness=0;glint=0;use_alpha=0;bounded_alpha=0;alpha_steps=0;
 half_width=0;front=0;distance=0;delta=0;projection=0;travel=0;center=640;metric=0;
 if(e0)case(fx0)
  3:begin // Eight independently projected cards, staggered in time.
   half_width=(({23'd0,scale0}<<2)+{23'd0,scale0})>>4;projection=product>>>10;
   if(magnitude(lx0)<=half_width&&scale0>=16)begin
    a=origin0+80+projection;b=a;
    use_alpha=1;
    darkness=(256-scale0)>>4;if(t0>0&&t0<256&&half_width-magnitude(lx0)<5)glint=3;
   end else begin a=u0;b=u0;mix=256;darkness=12;end
   // Reflection is shared after the mode geometry.
  end
  4:begin // Accordion: a progressively compressed texture with shaded folds.
   front=(256-p0);front=(front<<2)+front;a=product>>>10;b=u0;
   distance=$signed({1'b0,u0})-front;use_alpha=1;
   if(distance<0)begin
    metric=fold_phase(a[10:0]);darkness=metric<80 ? p0>>4:p0>>3;
    if(darkness>24)darkness=24;
    if(p0>8&&(metric<4||metric>=156))glint=2;
   end
   // Reflection is shared after the mode geometry.
  end
  5:begin // Metallic liquid front, local refraction, silver rim and shadow.
   projection=wave_product>>>7;front=({23'd0,p0}<<2)+({23'd0,p0}<<1)-128+projection;distance=$signed({1'b0,u0})-front;
   use_alpha=1;a=u0;b=u0;
   if((distance>-22'sd32&&distance<22'sd32))a=a+(distance>>>1);
   if(distance>0&&distance<32)darkness=6;
   glint=(distance>-22'sd6&&distance<22'sd6) ? 6:(distance>-22'sd16&&distance<22'sd16) ? 2:0;
   // Reflection is shared after the mode geometry.
  end
  7:begin // True circular distance squared; no square-root or frame buffer.
   delta=(wave_product<<<3)+wave_product-product-second_product;
   use_alpha=1;
   if((delta>-22'sd24576&&delta<22'sd24576))a=a+(delta>>>11);
   glint=(delta>-22'sd8192&&delta<22'sd8192) ? 7:(delta>-22'sd16384&&delta<22'sd16384) ? 2:0;
   if(delta<0&&delta>-24576)darkness=4;
  end
  8:begin // Slanted glass tiles slide independently, exposing the next image.
   travel=(product>>>8)<<1;distance=$signed(tilt0);distance=distance-(({30'd0,gc0}<<8)+({30'd0,gc0}<<6))+travel-320;
   a=u0+travel;b=u0;use_alpha=1;
   if(distance<16)darkness=t0>>5;
   if((distance>-22'sd5&&distance<22'sd5))glint=4;
   // Reflection is shared after the mode geometry.
  end
  9:begin // Horizontal tunnel: old panel contracts, new panel expands.
   a=640+(product>>>10);b=640+(second_product>>>10);
   half_width=({23'd0,p0}<<1)+{23'd0,p0};distance=half_width-magnitude($signed({1'b0,px0})-640);
   use_alpha=1;
   if(magnitude($signed({1'b0,px0})-640)>((((256-p0)<<2)+(256-p0))>>1)&&distance<0)darkness=24;
   else darkness=env0>>4;
   metric=magnitude($signed({1'b0,px0})-640)+magnitude($signed({1'b0,y0})-360);
   if(env0>16&&(metric&63)<3)begin glint=2;darkness=4;end
  end
  10:begin // Viscous split: both halves pull apart around a curved opening.
   half_width=product>>>8;half_width=(half_width<<1)+half_width;center=640+(wave_product>>>8);
   if(r0)center=1280-center;
   distance=half_width-magnitude($signed({1'b0,px0})-center);
   use_alpha=1;a=px0+(px0<center ? half_width:-half_width);
   if((distance>-22'sd24&&distance<22'sd24))a=a+(distance>>>2);
   if(distance<0&&distance>-32)darkness=8;
   glint=(distance>-22'sd5&&distance<22'sd5) ? 5:(distance>-22'sd12&&distance<22'sd12) ? 1:0;
  end
 endcase
 // One saturating alpha path and one reflection pair serve all mutually
 // exclusive modes. Select operands before the shared arithmetic.
 if(use_alpha)begin
  // Saturating 128 + (d << 3) is a five-bit biased code inside
  // -16..15. Outside that interval only the endpoint matters. The
  // portal uses the corresponding exact seven-bit fractional shift.
  // Select small operands before encoding instead of a 22-bit adder.
  if(fx0==7)begin
   if(delta < -22'sd16384)bounded_alpha=0;
   else if(delta >= 22'sd16384)bounded_alpha=256;
   else bounded_alpha={1'b0,~delta[14],delta[13:7]};
  end else if(fx0==3)begin
   if(t0<112)bounded_alpha=0;
   else if(t0>=144)bounded_alpha=256;
   else bounded_alpha={1'b0,~t0[4],t0[3:0],3'd0};
  end else begin
   alpha_steps=fx0==5 ? -distance[4:0]:distance[4:0];
   if(distance < -14'sd16)bounded_alpha=fx0==5 ? 256:0;
   else if(distance >= 14'sd16)bounded_alpha=fx0==5 ? 0:256;
   else if(fx0==5 && distance==-14'sd16)bounded_alpha=256;
   else bounded_alpha={1'b0,~alpha_steps[4],alpha_steps[3:0],3'd0};
  end
  mix=$signed({1'b0,bounded_alpha});
 end
 if(e0 && r0 && (fx0==3 || fx0==4 || fx0==5 || fx0==8))begin
  a=17'sd1279-a;b=17'sd1279-b;
 end
 if(!e0||p0==0||p0==256)begin
  a={wx0,1'b0};b=px0;mix=e0 ? p0:0;darkness=0;glint=0;
 end
end
reg signed[16:0] a_d,b_d;
reg[8:0] mix_d;reg[4:0] shade_d;reg[2:0] shine_d;
reg[9:0] old_y_d,x_d,y_d;reg valid_d;
always @(posedge clk)begin
 a_d<=a;b_d<=b;mix_d<=mix[8:0];shade_d<=darkness[4:0];shine_d<=glint[2:0];
 old_y_d<=e0 ? y0:wy0;x_d<=x0;y_d<=y0;valid_d<=v0&&!rst;
 out_valid<=valid_d&&!rst;old_x<=clipped_word(a_d);new_x<=clipped_word(b_d);
 old_y<=old_y_d;out_x<=x_d;out_y<=y_d;
 alpha<=mix_d;shade<=shade_d;shine<=shine_d;
end
endmodule

// The 512 x 16 shared projection/portal table fits exactly in one RAM9K.
module water_effect_recip_rom_before(input clk,input[8:0] address,output[15:0] value);
`ifdef WATER_SIM
reg[15:0] memory[0:511];reg[15:0] data_q;
initial $readmemh({`FX11_ROM_ROOT,"water_fx_recip.hex"},memory);
always @(posedge clk)data_q<=memory[address];
assign value=data_q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),
 .MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
 .IMPLEMENT("9K"),.INIT_FILE("water_fx_recip.mif")) rom(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(1'b0),.ocea(1'b1),.bea(1'b0),
 .addra(address),.dia(16'd0),.doa(value),
 .clkb(clk),.rstb(1'b0),.ceb(1'b0),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb(9'd0),.dib(16'd0),.dob());
`endif
endmodule

module water_wave_multiply_before(input signed[6:0] a,input[7:0] b,output signed[15:0] value);
`ifdef FX11_NATIVE_DSP
wire[35:0] product;
EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),.OUTPUTREG("DISABLE")) multiply(
 .a({{11{a[6]}},a}),.b({10'd0,b}),.p(product),.signeda(1'b1),.signedb(1'b0),
 .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
 .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(1'b0),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
assign value=product[15:0];
`else
assign value=$signed(a)*$signed({1'b0,b});
`endif
endmodule
