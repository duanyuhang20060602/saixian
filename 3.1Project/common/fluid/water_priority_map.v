// Port of water-single a15d24f: curl, metal, columns, card, accordion, ribbon.
// Six registered stages; all texture samples stay on the current source row.
module water_priority_map(input clk,rst,valid,enabled,right,input[3:0] effect,
 input[8:0] progress,input[9:0] ox,oy,
 output reg out_valid,output reg[9:0] old_x,old_y,new_x,out_x,out_y,
 output reg[8:0] alpha,output reg[4:0] shade,output reg[2:0] shine);
wire[10:0] px={ox,1'b0};
wire[10:0] oriented=right ? 11'd1279-px:px;
reg[2:0] column;
always @*begin
 if(oriented<160)column=0;else if(oriented<320)column=1;
 else if(oriented<480)column=2;else if(oriented<640)column=3;
 else if(oriented<800)column=4;else if(oriented<960)column=5;
 else if(oriented<1120)column=6;else column=7;
end
reg[10:0] u[0:3],origin[0:3];reg[9:0] x[0:3],y[0:3];
reg[8:0] p[0:3],t[1:3],scale[1:3];reg[3:0] fx[0:3];
reg[3:0] vp,ep,rp;reg[2:0] column0,ribbon_order0;
reg[6:0] ribbon_row0;
reg[2:0] ribbon_band;reg[6:0] ribbon_row;
always @*begin
 if(oy<90)begin ribbon_band=0;ribbon_row=oy;end
 else if(oy<180)begin ribbon_band=1;ribbon_row=oy-90;end
 else if(oy<270)begin ribbon_band=2;ribbon_row=oy-180;end
 else if(oy<360)begin ribbon_band=3;ribbon_row=oy-270;end
 else if(oy<450)begin ribbon_band=4;ribbon_row=oy-360;end
 else if(oy<540)begin ribbon_band=5;ribbon_row=oy-450;end
 else if(oy<630)begin ribbon_band=6;ribbon_row=oy-540;end
 else begin ribbon_band=7;ribbon_row=oy-630;end
end
wire signed[12:0] stagger=fx[0]==3 ?
 $signed({4'd0,p[0]})+$signed({5'd0,p[0][8:1]})-$signed({6'd0,column0,4'd0}):
 fx[0]==2 ? $signed({4'd0,p[0]})+$signed({6'd0,p[0][8:2]})-$signed({7'd0,ribbon_order0,3'd0}):
 $signed({4'd0,p[0]});
wire[8:0] local_t=stagger<0 ? 9'd0:stagger>256 ? 9'd256:stagger[8:0];
wire[8:0] local_scale=fx[0]==4 ? 9'd256-p[0]:local_t<128 ? 9'd256-(local_t<<1):(local_t<<1)-9'd256;
wire[8:0] reciprocal_address=fx[1]!=4 && scale[1]<16 ? 9'd16:scale[1];
wire[15:0] reciprocal;
// Keep the 512x16 reciprocal in one RAM9K rather than spending RAM32K.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(9),.DATA_DEPTH_A(512),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(9),.DATA_DEPTH_B(512),.BYTE_ENABLE(0),
 .MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
 .INIT_FILE("water_column_recip.mif"),.IMPLEMENT("9K")) reciprocal_rom(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(1'b0),.ocea(1'b0),.bea(1'b0),
 .addra(reciprocal_address),.dia(16'd0),.doa(reciprocal),
 .clkb(1'b0),.rstb(1'b0),.ceb(1'b0),.web(1'b0),.oceb(1'b0),.beb(1'b0),
 .addrb(9'd0),.dib(16'd0),.dob());
// The source curl's 32-entry curve is embedded as logic by the asset generator.
function[13:0] curl_curve;input[4:0] a;begin case(a)
 0:curl_curve=14'h3860;
 1:curl_curve=14'h375e;
 2:curl_curve=14'h365c;
 3:curl_curve=14'h355a;
 4:curl_curve=14'h1458;
 5:curl_curve=14'h1256;
 6:curl_curve=14'h1154;
 7:curl_curve=14'h1053;
 8:curl_curve=14'h0f51;
 9:curl_curve=14'h0e4f;
 10:curl_curve=14'h0d4d;
 11:curl_curve=14'h0c4b;
 12:curl_curve=14'h0c49;
 13:curl_curve=14'h0b46;
 14:curl_curve=14'h0a44;
 15:curl_curve=14'h0942;
 16:curl_curve=14'h0840;
 17:curl_curve=14'h073e;
 18:curl_curve=14'h073b;
 19:curl_curve=14'h0639;
 20:curl_curve=14'h0537;
 21:curl_curve=14'h0434;
 22:curl_curve=14'h0432;
 23:curl_curve=14'h032f;
 24:curl_curve=14'h032c;
 25:curl_curve=14'h0229;
 26:curl_curve=14'h0226;
 27:curl_curve=14'h0123;
 28:curl_curve=14'h011f;
 29:curl_curve=14'h001b;
 30:curl_curve=14'h0016;
 31:curl_curve=14'h000f;
 default:curl_curve=0;
endcase end endfunction
function signed[6:0] ribbon_curve;input[6:0] row;begin case(row)
 0:ribbon_curve=7'h00;
 1:ribbon_curve=7'h01;
 2:ribbon_curve=7'h02;
 3:ribbon_curve=7'h03;
 4:ribbon_curve=7'h03;
 5:ribbon_curve=7'h04;
 6:ribbon_curve=7'h05;
 7:ribbon_curve=7'h06;
 8:ribbon_curve=7'h07;
 9:ribbon_curve=7'h07;
 10:ribbon_curve=7'h08;
 11:ribbon_curve=7'h09;
 12:ribbon_curve=7'h0a;
 13:ribbon_curve=7'h0b;
 14:ribbon_curve=7'h0b;
 15:ribbon_curve=7'h0c;
 16:ribbon_curve=7'h0d;
 17:ribbon_curve=7'h0d;
 18:ribbon_curve=7'h0e;
 19:ribbon_curve=7'h0f;
 20:ribbon_curve=7'h0f;
 21:ribbon_curve=7'h10;
 22:ribbon_curve=7'h11;
 23:ribbon_curve=7'h11;
 24:ribbon_curve=7'h12;
 25:ribbon_curve=7'h12;
 26:ribbon_curve=7'h13;
 27:ribbon_curve=7'h13;
 28:ribbon_curve=7'h14;
 29:ribbon_curve=7'h14;
 30:ribbon_curve=7'h15;
 31:ribbon_curve=7'h15;
 32:ribbon_curve=7'h16;
 33:ribbon_curve=7'h16;
 34:ribbon_curve=7'h16;
 35:ribbon_curve=7'h17;
 36:ribbon_curve=7'h17;
 37:ribbon_curve=7'h17;
 38:ribbon_curve=7'h17;
 39:ribbon_curve=7'h17;
 40:ribbon_curve=7'h18;
 41:ribbon_curve=7'h18;
 42:ribbon_curve=7'h18;
 43:ribbon_curve=7'h18;
 44:ribbon_curve=7'h18;
 45:ribbon_curve=7'h18;
 46:ribbon_curve=7'h18;
 47:ribbon_curve=7'h18;
 48:ribbon_curve=7'h18;
 49:ribbon_curve=7'h18;
 50:ribbon_curve=7'h18;
 51:ribbon_curve=7'h17;
 52:ribbon_curve=7'h17;
 53:ribbon_curve=7'h17;
 54:ribbon_curve=7'h17;
 55:ribbon_curve=7'h17;
 56:ribbon_curve=7'h16;
 57:ribbon_curve=7'h16;
 58:ribbon_curve=7'h16;
 59:ribbon_curve=7'h15;
 60:ribbon_curve=7'h15;
 61:ribbon_curve=7'h14;
 62:ribbon_curve=7'h14;
 63:ribbon_curve=7'h13;
 64:ribbon_curve=7'h13;
 65:ribbon_curve=7'h12;
 66:ribbon_curve=7'h12;
 67:ribbon_curve=7'h11;
 68:ribbon_curve=7'h11;
 69:ribbon_curve=7'h10;
 70:ribbon_curve=7'h0f;
 71:ribbon_curve=7'h0f;
 72:ribbon_curve=7'h0e;
 73:ribbon_curve=7'h0d;
 74:ribbon_curve=7'h0d;
 75:ribbon_curve=7'h0c;
 76:ribbon_curve=7'h0b;
 77:ribbon_curve=7'h0b;
 78:ribbon_curve=7'h0a;
 79:ribbon_curve=7'h09;
 80:ribbon_curve=7'h08;
 81:ribbon_curve=7'h07;
 82:ribbon_curve=7'h07;
 83:ribbon_curve=7'h06;
 84:ribbon_curve=7'h05;
 85:ribbon_curve=7'h04;
 86:ribbon_curve=7'h03;
 87:ribbon_curve=7'h03;
 88:ribbon_curve=7'h02;
 89:ribbon_curve=7'h01;
 default:ribbon_curve=0;
endcase end endfunction
wire signed[14:0] curl_front1=($signed({6'd0,p[1]})<<<2)+($signed({6'd0,p[1]})<<<1)-15'sd128;
wire signed[14:0] curl_distance1=$signed({4'd0,u[1]})-curl_front1;
reg[13:0] curve2,curve3;
wire[5:0] wave_phase=y[1][5:0]+p[1][5:0];
wire signed[6:0] wave_value=wave_phase[5] ? 7'sd47-$signed({1'b0,wave_phase}):$signed({1'b0,wave_phase})-7'sd16;
reg signed[6:0] wave2;reg[8:0] envelope2;
reg[6:0] ribbon_row1;
reg signed[16:0] projection_operand1,projection_operand2;
reg signed[33:0] projection3;reg signed[16:0] bend3;
integer i;
always @(posedge clk)begin
 u[0]<=oriented;origin[0]<=({8'd0,column}<<7)+({8'd0,column}<<5);
 column0<=column;ribbon_row0<=ribbon_row;ribbon_order0<={ribbon_band[0],ribbon_band[2:1]};x[0]<=ox;y[0]<=oy;p[0]<=progress;fx[0]<=effect;
 vp<={vp[2:0],valid&&!rst};ep<={ep[2:0],enabled};rp<={rp[2:0],right};
 for(i=1;i<4;i=i+1)begin u[i]<=u[i-1];origin[i]<=origin[i-1];x[i]<=x[i-1];y[i]<=y[i-1];p[i]<=p[i-1];fx[i]<=fx[i-1];end
 t[1]<=local_t;scale[1]<=local_scale;
 projection_operand1<=fx[0]==1 ? $signed({6'd0,u[0]})-17'sd640:
  fx[0]==4 ? $signed({6'd0,u[0]}):
  fx[0]==2 ? $signed({8'd0,local_t}):
  $signed({6'd0,u[0]})-$signed({6'd0,origin[0]})-17'sd80;
 projection_operand2<=projection_operand1;
 ribbon_row1<=ribbon_row0;
 for(i=2;i<4;i=i+1)begin t[i]<=t[i-1];scale[i]<=scale[i-1];end
 curve2<=curl_curve(curl_distance1[6:2]);curve3<=curve2;
 wave2<=fx[1]==2 ? ribbon_curve(ribbon_row1):wave_value;
 envelope2<=fx[1]==2 ? (t[1]<128 ? t[1]:9'd256-t[1]):(p[1]<128 ? p[1]:9'd256-p[1]);
 projection3<=projection_operand2*(fx[2]==2 ? $signed({8'd0,t[2]}):$signed({1'b0,reciprocal}));
 bend3<=wave2*$signed({1'b0,envelope2});
 if(rst)vp<=0;
end
function[8:0] weight;input signed[21:0] n;begin weight=n<0 ? 0:n>256 ? 256:n[8:0];end endfunction
function[9:0] word_clip;input signed[21:0] n;begin word_clip=n<0 ? 0:n>1278 ? 639:n[10:1];end endfunction
function signed[21:0] magnitude;input signed[21:0] n;begin magnitude=n<0 ? -n:n;end endfunction
function[7:0] fold_phase;input[10:0] pos;begin
 if(pos<160)fold_phase=pos;else if(pos<320)fold_phase=pos-160;
 else if(pos<480)fold_phase=pos-320;else if(pos<640)fold_phase=pos-480;
 else if(pos<800)fold_phase=pos-640;else if(pos<960)fold_phase=pos-800;
 else if(pos<1120)fold_phase=pos-960;else fold_phase=pos-1120;
end endfunction
reg signed[21:0] a,b,front,distance,half_width,projected,local_abs,travel,ease;
reg[7:0] fold;
reg[8:0] mix;reg[4:0] dark;reg[2:0] light;
always @*begin
 a=$signed({12'd0,x[3],1'b0});b=a;mix=p[3];dark=0;light=0;
 front=0;distance=0;half_width=0;projected=0;local_abs=0;travel=0;ease=0;fold=0;
 if(ep[3])case(fx[3])
  0:begin // Reflected curl, rounded lip, cast shadow and highlight.
   front=($signed({13'd0,p[3]})<<<2)+($signed({13'd0,p[3]})<<<1)-128;
   distance=$signed({11'd0,u[3]})-front;mix=weight(128-(distance<<<3));
   a=$signed({11'd0,u[3]});
   if(distance>=0&&distance<128)begin a=front+$signed({14'd0,curve3[7:0]});dark=curve3[12:8];light={2'd0,curve3[13]};end
   if(rp[3])a=1279-a;
  end
  1:begin // Whole card shares the column reciprocal and projection DSP.
   half_width=($signed({13'd0,scale[3]})<<<1)+$signed({14'd0,scale[3][8:1]});
   local_abs=magnitude($signed({11'd0,u[3]})-640);
   if(local_abs<=half_width&&scale[3]>=16)begin
    a=640+(projection3>>>10);b=a;
    mix=p[3]<112 ? 0:p[3]>=144 ? 256:(p[3]-112)<<3;
    dark=(9'd256-scale[3])>>4;
    if(half_width-local_abs<8)light=3;
   end else begin dark=28;mix=p[3];a=u[3];b=u[3];end
   if(rp[3])begin a=1279-a;b=1279-b;end
  end
  2:begin // Eight woven ribbons; exact source curve, stagger and eased travel.
   ease=($signed({13'd0,t[3]})<<<1)-(projection3>>>8);
   travel=(ease<<<2)+ease+(bend3>>>7);front=1280-travel;
   distance=$signed({11'd0,u[3]})-front;
   mix=weight(128+(distance<<<3));a=$signed({11'd0,u[3]})+travel;b=a-1280;
   if(rp[3])begin a=1279-a;b=1279-b;end
   if(t[3]>0&&t[3]<256)begin dark=2;if(distance>-12&&distance<12)light=2;end
  end
  4:begin // Compressed accordion with eight alternating lit/shaded folds.
   front=($signed({13'd0,scale[3]})<<<2)+$signed({13'd0,scale[3]});
   a=projection3>>>10;b=u[3];distance=$signed({11'd0,u[3]})-front;
   mix=weight(128+(distance<<<3));
   if(distance<0)begin
    fold=fold_phase(a[10:0]);dark=fold<80 ? p[3]>>4:p[3]>>3;
    if(dark>24)dark=24;
    if(p[3]>8&&(fold<4||fold>=156))light=2;
   end
   if(rp[3])begin a=1279-a;b=1279-b;end
  end
  3:begin // Eight independently projected columns with staggered phase.
   half_width=(($signed({13'd0,scale[3]})<<<2)+$signed({13'd0,scale[3]}))>>>4;
   projected=projection3>>>10;
   local_abs=magnitude($signed({11'd0,u[3]})-$signed({11'd0,origin[3]})-80);
   if(local_abs<=half_width&&scale[3]>=16)begin
    a=$signed({11'd0,origin[3]})+80+projected;b=a;
    mix=t[3]<112 ? 0:t[3]>=144 ? 256:(t[3]-112)<<3;
    dark=(9'd256-scale[3])>>4;
    if(t[3]>0&&t[3]<256&&half_width-local_abs<5)light=3;
   end else begin a=u[3];b=u[3];mix=256;dark=12;end
   if(rp[3])begin a=1279-a;b=1279-b;end
  end
  5:begin // Metallic front with local refraction and a bright silver rim.
   front=($signed({13'd0,p[3]})<<<2)+($signed({13'd0,p[3]})<<<1)-128+(bend3>>>7);
   distance=$signed({11'd0,u[3]})-front;mix=weight(128-(distance<<<3));a=u[3];b=u[3];
   if(magnitude(distance)<32)a=a+(distance>>>1);
   if(distance>0&&distance<32)dark=6;
   light=magnitude(distance)<6 ? 6:magnitude(distance)<16 ? 2:0;
   if(rp[3])begin a=1279-a;b=1279-b;end
  end
 endcase
 if(!ep[3]||p[3]==0||p[3]==256)begin
  a={x[3],1'b0};b=a;mix=!ep[3] ? 0:p[3];dark=0;light=0;
 end
end
reg signed[21:0] a4,b4;reg[8:0] mix4;reg[4:0] dark4;reg[2:0] light4;
reg[9:0] x4,y4;reg v4;
always @(posedge clk)begin
 a4<=a;b4<=b;mix4<=mix;dark4<=dark;light4<=light;x4<=x[3];y4<=y[3];v4<=vp[3]&&!rst;
 old_x<=word_clip(a4);new_x<=word_clip(b4);old_y<=y4;out_x<=x4;out_y<=y4;
 alpha<=mix4;shade<=dark4;shine<=light4;out_valid<=v4&&!rst;
end
endmodule

// Both geometry alternatives have the same six-stage output contract.
module water_effect_map(input clk,rst,valid,enabled,right,input[3:0] effect,
 input[8:0] progress,input[9:0] ox,oy,wx,wy,
 output out_valid,output[9:0] old_x,old_y,new_x,out_x,out_y,
 output[8:0] alpha,output[4:0] shade,output[2:0] shine);
wire[67:0] ripple,priority_pixel;reg[67:0] ripple_delay[0:3];integer j;
water_ripple_map ripple_map(.clk(clk),.rst(rst),.valid(valid),.enabled(enabled),.right(right),.effect(effect),
 .progress(progress),.ox(ox),.oy(oy),.wx(wx),.wy(wy),
 .out_valid(ripple[67]),.old_x(ripple[66:57]),.old_y(ripple[56:47]),.new_x(ripple[46:37]),
 .out_x(ripple[36:27]),.out_y(ripple[26:17]),.alpha(ripple[16:8]),.shade(ripple[7:3]),.shine(ripple[2:0]));
always @(posedge clk)begin
 ripple_delay[0]<=rst ? 68'd0:ripple;
 for(j=1;j<4;j=j+1)ripple_delay[j]<=rst ? 68'd0:ripple_delay[j-1];
end
water_priority_map priority_map(.clk(clk),.rst(rst),.valid(valid),.enabled(enabled),.right(right),.effect(effect),
 .progress(progress),.ox(ox),.oy(oy),.out_valid(priority_pixel[67]),
 .old_x(priority_pixel[66:57]),.old_y(priority_pixel[56:47]),.new_x(priority_pixel[46:37]),
 .out_x(priority_pixel[36:27]),.out_y(priority_pixel[26:17]),.alpha(priority_pixel[16:8]),.shade(priority_pixel[7:3]),.shine(priority_pixel[2:0]));
assign {out_valid,old_x,old_y,new_x,out_x,out_y,alpha,shade,shine}=effect==6 ? ripple_delay[3]:priority_pixel;
endmodule
