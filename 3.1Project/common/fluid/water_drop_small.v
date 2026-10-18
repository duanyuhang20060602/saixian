// Small-halo procedural refraction. Octagonal distance avoids sqrt/reciprocal
// ROMs; no stored animation frames, vertical displacement never exceeds 2.
module water_warp(input clk,rst,valid,input[9:0] xword,y,input water_mode,input[8:0] progress,
 input drop0,drop1,input[10:0] cx0,cx1,input[9:0] cy0,cy1,input[11:0] radius0,radius1,
 output reg out_valid,output reg[9:0] sxword,sy,out_xword,out_y);
wire signed[11:0] dx=$signed({1'b0,xword,1'b0})-12'sd640;
wire signed[11:0] dy=$signed({2'b0,y})-12'sd360;
wire[10:0] ax=dx<0 ? -dx:dx,ay=dy<0 ? -dy:dy;
reg[11:0] distance_q;reg sign_x,sign_y,v0;
reg[9:0] x0,y0;reg[8:0] p0;reg enabled0;
always @(posedge clk)begin
 distance_q<=ax>ay ? ax+(ay>>1):ay+(ax>>1);
 sign_x<=dx<0;sign_y<=dy<0;x0<=xword;y0<=y;p0<=progress;
 enabled0<=water_mode;v0<=valid&&!rst;
end
wire[11:0] phase=distance_q-({3'd0,p0}<<1);
wire[2:0] magnitude=phase[4:2];
wire[3:0] amplitude=phase[5] ? 4'd7-{1'b0,magnitude}:{1'b0,magnitude};
wire active=enabled0&&p0>0&&p0<256;
wire reverse_x=sign_x^phase[6],reverse_y=sign_y^phase[6];
wire signed[12:0] shift_x=active ? $signed({8'd0,amplitude,1'b0}):13'sd0;
wire signed[12:0] shift_y=active ? $signed({11'd0,amplitude[2:1]}):13'sd0;
// amplitude[2:1] is 0..3; clamp the vertical halo to two rows.
wire signed[12:0] limited_y=shift_y>2 ? 13'sd2:shift_y;
wire signed[12:0] tx=$signed({2'd0,x0,1'b0})+(reverse_x ? -shift_x:shift_x);
wire signed[12:0] ty=$signed({3'd0,y0})+(reverse_y ? -limited_y:limited_y);
always @(posedge clk)begin
 out_valid<=v0&&!rst;out_xword<=x0;out_y<=y0;
 sxword<=tx<0 ? 10'd0:tx>1278 ? 10'd639:tx[10:1];
 sy<=ty<0 ? 10'd0:ty>719 ? 10'd719:ty[9:0];
end
endmodule

// Two stages match the mapping/light metadata contract of the source reader.
module water_ripple_map(input clk,rst,valid,enabled,right,input[3:0] effect,
 input[8:0] progress,input[9:0] ox,oy,wx,wy,
 output reg out_valid,output reg[9:0] old_x,old_y,new_x,out_x,out_y,
 output reg[8:0] alpha,output reg[4:0] shade,output reg[2:0] shine);
wire signed[11:0] dx=$signed({1'b0,ox,1'b0})-12'sd640;
wire signed[11:0] dy=$signed({2'b0,oy})-12'sd360;
wire[10:0] ax=dx<0 ? -dx:dx,ay=dy<0 ? -dy:dy;
reg[11:0] distance_q;reg[9:0] xq,yq,wxq,wyq;reg[8:0] pq;
reg eq,vq;
always @(posedge clk)begin
 distance_q<=ax>ay ? ax+(ay>>1):ay+(ax>>1);
 xq<=ox;yq<=oy;wxq<=wx;wyq<=wy;pq<=progress;eq<=enabled;vq<=valid&&!rst;
end
wire signed[13:0] front=$signed({5'd0,pq,2'b0})-14'sd96;
wire signed[13:0] edge_distance=front-$signed({2'd0,distance_q});
wire signed[13:0] weight=14'sd128+(edge_distance<<<2);
wire middle=eq&&pq>0&&pq<256;
always @(posedge clk)begin
 out_valid<=vq&&!rst;out_x<=xq;out_y<=yq;
 old_x<=middle ? wxq:xq;old_y<=middle ? wyq:yq;new_x<=xq;
 alpha<=!eq||pq==0 ? 9'd0:pq==256 ? 9'd256:weight<0 ? 9'd0:weight>256 ? 9'd256:weight[8:0];
 shade<=middle&&edge_distance>-12&&edge_distance<0 ? 5'd4:5'd0;
 shine<=middle&&edge_distance>=0&&edge_distance<12 ? 3'd1:3'd0;
end
endmodule
