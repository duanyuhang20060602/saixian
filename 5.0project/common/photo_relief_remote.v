// B evaluates the exact 5.0 material response once per palette entry.
// A keeps scanout and row decoding. Tables change atomically at vertical blank.
module photo_relief_shade_kernel(input clk,rst,input [31:0] material,
 input signed [5:0] light_x,light_y,input wall,input [6:0] wall_level,
 output [23:0] rgb);
wire cup=!wall;
wire [15:0] surface=material[15:0],base_color=material[31:16];
function [23:0] expand;input [15:0] p;begin
 expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
// Logic-array products retain the original stage-4 latency; both DSPs serve diffuse shading.
function [7:0] sat;input [8:0] a;begin sat=a[8]?8'd255:a[7:0];end endfunction
function [7:0] exposure2;input [7:0] c;begin case(c)
8'd0:exposure2=8'd0;
8'd1:exposure2=8'd2;
8'd2:exposure2=8'd4;
8'd3:exposure2=8'd6;
8'd4:exposure2=8'd8;
8'd5:exposure2=8'd10;
8'd6:exposure2=8'd12;
8'd7:exposure2=8'd14;
8'd8:exposure2=8'd16;
8'd9:exposure2=8'd17;
8'd10:exposure2=8'd19;
8'd11:exposure2=8'd21;
8'd12:exposure2=8'd23;
8'd13:exposure2=8'd25;
8'd14:exposure2=8'd27;
8'd15:exposure2=8'd28;
8'd16:exposure2=8'd30;
8'd17:exposure2=8'd32;
8'd18:exposure2=8'd34;
8'd19:exposure2=8'd35;
8'd20:exposure2=8'd37;
8'd21:exposure2=8'd39;
8'd22:exposure2=8'd41;
8'd23:exposure2=8'd42;
8'd24:exposure2=8'd44;
8'd25:exposure2=8'd46;
8'd26:exposure2=8'd47;
8'd27:exposure2=8'd49;
8'd28:exposure2=8'd50;
8'd29:exposure2=8'd52;
8'd30:exposure2=8'd54;
8'd31:exposure2=8'd55;
8'd32:exposure2=8'd57;
8'd33:exposure2=8'd58;
8'd34:exposure2=8'd60;
8'd35:exposure2=8'd62;
8'd36:exposure2=8'd63;
8'd37:exposure2=8'd65;
8'd38:exposure2=8'd66;
8'd39:exposure2=8'd68;
8'd40:exposure2=8'd69;
8'd41:exposure2=8'd71;
8'd42:exposure2=8'd72;
8'd43:exposure2=8'd74;
8'd44:exposure2=8'd75;
8'd45:exposure2=8'd76;
8'd46:exposure2=8'd78;
8'd47:exposure2=8'd79;
8'd48:exposure2=8'd81;
8'd49:exposure2=8'd82;
8'd50:exposure2=8'd84;
8'd51:exposure2=8'd85;
8'd52:exposure2=8'd86;
8'd53:exposure2=8'd88;
8'd54:exposure2=8'd89;
8'd55:exposure2=8'd90;
8'd56:exposure2=8'd92;
8'd57:exposure2=8'd93;
8'd58:exposure2=8'd95;
8'd59:exposure2=8'd96;
8'd60:exposure2=8'd97;
8'd61:exposure2=8'd98;
8'd62:exposure2=8'd100;
8'd63:exposure2=8'd101;
8'd64:exposure2=8'd102;
8'd65:exposure2=8'd104;
8'd66:exposure2=8'd105;
8'd67:exposure2=8'd106;
8'd68:exposure2=8'd107;
8'd69:exposure2=8'd109;
8'd70:exposure2=8'd110;
8'd71:exposure2=8'd111;
8'd72:exposure2=8'd112;
8'd73:exposure2=8'd114;
8'd74:exposure2=8'd115;
8'd75:exposure2=8'd116;
8'd76:exposure2=8'd117;
8'd77:exposure2=8'd118;
8'd78:exposure2=8'd119;
8'd79:exposure2=8'd121;
8'd80:exposure2=8'd122;
8'd81:exposure2=8'd123;
8'd82:exposure2=8'd124;
8'd83:exposure2=8'd125;
8'd84:exposure2=8'd126;
8'd85:exposure2=8'd128;
8'd86:exposure2=8'd129;
8'd87:exposure2=8'd130;
8'd88:exposure2=8'd131;
8'd89:exposure2=8'd132;
8'd90:exposure2=8'd133;
8'd91:exposure2=8'd134;
8'd92:exposure2=8'd135;
8'd93:exposure2=8'd136;
8'd94:exposure2=8'd137;
8'd95:exposure2=8'd138;
8'd96:exposure2=8'd139;
8'd97:exposure2=8'd141;
8'd98:exposure2=8'd142;
8'd99:exposure2=8'd143;
8'd100:exposure2=8'd144;
8'd101:exposure2=8'd145;
8'd102:exposure2=8'd146;
8'd103:exposure2=8'd147;
8'd104:exposure2=8'd148;
8'd105:exposure2=8'd149;
8'd106:exposure2=8'd150;
8'd107:exposure2=8'd151;
8'd108:exposure2=8'd152;
8'd109:exposure2=8'd153;
8'd110:exposure2=8'd154;
8'd111:exposure2=8'd155;
8'd112:exposure2=8'd156;
8'd113:exposure2=8'd157;
8'd114:exposure2=8'd158;
8'd115:exposure2=8'd159;
8'd116:exposure2=8'd159;
8'd117:exposure2=8'd160;
8'd118:exposure2=8'd161;
8'd119:exposure2=8'd162;
8'd120:exposure2=8'd163;
8'd121:exposure2=8'd164;
8'd122:exposure2=8'd165;
8'd123:exposure2=8'd166;
8'd124:exposure2=8'd167;
8'd125:exposure2=8'd168;
8'd126:exposure2=8'd169;
8'd127:exposure2=8'd170;
8'd128:exposure2=8'd170;
8'd129:exposure2=8'd171;
8'd130:exposure2=8'd172;
8'd131:exposure2=8'd173;
8'd132:exposure2=8'd174;
8'd133:exposure2=8'd175;
8'd134:exposure2=8'd176;
8'd135:exposure2=8'd177;
8'd136:exposure2=8'd177;
8'd137:exposure2=8'd178;
8'd138:exposure2=8'd179;
8'd139:exposure2=8'd180;
8'd140:exposure2=8'd181;
8'd141:exposure2=8'd182;
8'd142:exposure2=8'd182;
8'd143:exposure2=8'd183;
8'd144:exposure2=8'd184;
8'd145:exposure2=8'd185;
8'd146:exposure2=8'd186;
8'd147:exposure2=8'd186;
8'd148:exposure2=8'd187;
8'd149:exposure2=8'd188;
8'd150:exposure2=8'd189;
8'd151:exposure2=8'd190;
8'd152:exposure2=8'd190;
8'd153:exposure2=8'd191;
8'd154:exposure2=8'd192;
8'd155:exposure2=8'd193;
8'd156:exposure2=8'd194;
8'd157:exposure2=8'd194;
8'd158:exposure2=8'd195;
8'd159:exposure2=8'd196;
8'd160:exposure2=8'd197;
8'd161:exposure2=8'd197;
8'd162:exposure2=8'd198;
8'd163:exposure2=8'd199;
8'd164:exposure2=8'd200;
8'd165:exposure2=8'd200;
8'd166:exposure2=8'd201;
8'd167:exposure2=8'd202;
8'd168:exposure2=8'd203;
8'd169:exposure2=8'd203;
8'd170:exposure2=8'd204;
8'd171:exposure2=8'd205;
8'd172:exposure2=8'd205;
8'd173:exposure2=8'd206;
8'd174:exposure2=8'd207;
8'd175:exposure2=8'd208;
8'd176:exposure2=8'd208;
8'd177:exposure2=8'd209;
8'd178:exposure2=8'd210;
8'd179:exposure2=8'd210;
8'd180:exposure2=8'd211;
8'd181:exposure2=8'd212;
8'd182:exposure2=8'd212;
8'd183:exposure2=8'd213;
8'd184:exposure2=8'd214;
8'd185:exposure2=8'd214;
8'd186:exposure2=8'd215;
8'd187:exposure2=8'd216;
8'd188:exposure2=8'd216;
8'd189:exposure2=8'd217;
8'd190:exposure2=8'd218;
8'd191:exposure2=8'd218;
8'd192:exposure2=8'd219;
8'd193:exposure2=8'd220;
8'd194:exposure2=8'd220;
8'd195:exposure2=8'd221;
8'd196:exposure2=8'd222;
8'd197:exposure2=8'd222;
8'd198:exposure2=8'd223;
8'd199:exposure2=8'd224;
8'd200:exposure2=8'd224;
8'd201:exposure2=8'd225;
8'd202:exposure2=8'd225;
8'd203:exposure2=8'd226;
8'd204:exposure2=8'd227;
8'd205:exposure2=8'd227;
8'd206:exposure2=8'd228;
8'd207:exposure2=8'd229;
8'd208:exposure2=8'd229;
8'd209:exposure2=8'd230;
8'd210:exposure2=8'd230;
8'd211:exposure2=8'd231;
8'd212:exposure2=8'd232;
8'd213:exposure2=8'd232;
8'd214:exposure2=8'd233;
8'd215:exposure2=8'd233;
8'd216:exposure2=8'd234;
8'd217:exposure2=8'd234;
8'd218:exposure2=8'd235;
8'd219:exposure2=8'd236;
8'd220:exposure2=8'd236;
8'd221:exposure2=8'd237;
8'd222:exposure2=8'd237;
8'd223:exposure2=8'd238;
8'd224:exposure2=8'd238;
8'd225:exposure2=8'd239;
8'd226:exposure2=8'd240;
8'd227:exposure2=8'd240;
8'd228:exposure2=8'd241;
8'd229:exposure2=8'd241;
8'd230:exposure2=8'd242;
8'd231:exposure2=8'd242;
8'd232:exposure2=8'd243;
8'd233:exposure2=8'd244;
8'd234:exposure2=8'd244;
8'd235:exposure2=8'd245;
8'd236:exposure2=8'd245;
8'd237:exposure2=8'd246;
8'd238:exposure2=8'd246;
8'd239:exposure2=8'd247;
8'd240:exposure2=8'd247;
8'd241:exposure2=8'd248;
8'd242:exposure2=8'd248;
8'd243:exposure2=8'd249;
8'd244:exposure2=8'd249;
8'd245:exposure2=8'd250;
8'd246:exposure2=8'd250;
8'd247:exposure2=8'd251;
8'd248:exposure2=8'd251;
8'd249:exposure2=8'd252;
8'd250:exposure2=8'd252;
8'd251:exposure2=8'd253;
8'd252:exposure2=8'd253;
8'd253:exposure2=8'd254;
8'd254:exposure2=8'd254;
8'd255:exposure2=8'd255;
default:exposure2=0;endcase end endfunction
reg signed [5:0] nx,ny;reg [4:0] nz;
reg [23:0] color3,color4,color5,color6;
reg [3:0] wall_pipe,cup_pipe;
wire signed [11:0] px,py;reg [9:0] pz;
photo_relief_remote_product product_x(.clk(clk),.rst(rst),.a(nx),.b(light_x),.p(px));
photo_relief_remote_product product_y(.clk(clk),.rst(rst),.a(ny),.b(light_y),.p(py));
reg signed [12:0] dot,half_dot;
reg [7:0] diffuse,specular;reg back;
wire signed [12:0] sum=$signed({px[11],px})+$signed({py[11],py})+$signed({3'b000,pz});
reg [23:0] delay8,delay9,delay10,delay11;
reg wall7;reg [6:0] wall_diffuse7;
wire [23:0] wall_shaded7={8'd24+{1'b0,wall_diffuse7},8'd12+{2'd0,wall_diffuse7[6:1]},8'd3+{4'd0,wall_diffuse7[6:3]}};
reg [23:0] color7;reg [7:0] specular7;reg cup7;
// Two 18x18 blocks carry all three full-precision diffuse channels. Red and
// blue each produce 13 bits; their 13-bit separation prevents any cross-carry.
wire [25:0] packed_diffuse,green_diffuse;
photo_relief_remote_lighting_product diffuse_rb(.clk(clk),.rst(rst),
 .a({color6[23:19],8'd0,color6[7:3]}),.b(diffuse),.p(packed_diffuse));
photo_relief_remote_lighting_product diffuse_g(.clk(clk),.rst(rst),
 .a({12'd0,color6[15:10]}),.b(diffuse),.p(green_diffuse));
wire [12:0] red_product=packed_diffuse[25:13],blue_product=packed_diffuse[12:0];
wire [13:0] green_product=green_diffuse[13:0];
// Expand RGB565 at sub-code precision: 33/4 for R/B, 65/16 for G. The
// diffuse result differs from exact RGB888 replication by at most one code.
wire [17:0] red_scaled={red_product,5'b0}+{5'b0,red_product};
wire [17:0] blue_scaled={blue_product,5'b0}+{5'b0,blue_product};
wire [19:0] green_scaled={green_product,6'b0}+{6'b0,green_product};
wire [7:0] fine_r={1'b0,red_scaled[17:11]},fine_b={1'b0,blue_scaled[17:11]};
wire [7:0] fine_g={1'b0,green_scaled[19:13]};
always @(posedge clk)begin
 // Stage 3: palette and background meet after the two synchronous RAM reads.
 nx<=$signed({surface[15:11],1'b0});ny<=$signed({surface[10:6],1'b0});nz<=surface[5:1];
 color3<=expand(base_color);wall_pipe<={wall_pipe[2:0],wall};cup_pipe<={cup_pipe[2:0],cup};
 // Stage 4.
 pz<={nz,4'b0000};color4<=color3;
 // Stage 5.
 dot<=sum;half_dot<=sum+$signed({3'b000,pz});color5<=color4;
 // Stage 6.
 diffuse<=dot<0 ? 8'd0:dot>1020 ? 8'd255:dot[9:2];
 specular<=half_dot<=1024 ? 8'd0:half_dot>=1279 ? 8'd255:(half_dot-13'sd1024);
 back<=dot<0;color6<=color5;
 // Stage 7: rough antique wall and polished gold cup use different response.
 // Store only the seven wall-light bits and tag; the colour pipeline
 // already retains the fallback RGB, so a second 24-bit RGB register is redundant.
 wall7<=wall_pipe[3];wall_diffuse7<=wall_level;
 // Stages 8..11 preserve the shared award menu/HDMI taps.
 color7<=color6;specular7<=specular;cup7<=cup_pipe[3];
 if(cup7)delay8<={
  sat({2'b00,color7[23:17]}+{1'b0,fine_r}+{2'b00,specular7[7:1]}),
  sat({2'b00,color7[15:9]}+{1'b0,fine_g}+{3'b000,specular7[7:2]}),
  sat({2'b00,color7[7:1]}+{1'b0,fine_b}+{4'b0000,specular7[7:3]})};
 else delay8<=wall7 ? wall_shaded7:color7;
 delay9<=delay8;delay10<=delay9;delay11<={exposure2(delay10[23:16]),exposure2(delay10[15:8]),exposure2(delay10[7:0])};
 if(rst)begin
  nx<=0;ny<=0;nz<=0;color3<=0;color4<=0;color5<=0;color6<=0;
  color7<=0;specular7<=0;cup7<=0;wall_pipe<=0;cup_pipe<=0;pz<=0;dot<=0;half_dot<=0;
  diffuse<=0;specular<=0;back<=0;wall7<=0;wall_diffuse7<=0;delay8<=0;delay9<=0;delay10<=0;delay11<=0;
 end
end
assign rgb=delay11;
endmodule
module photo_relief_remote_product(input clk,rst,input signed [5:0] a,b,output reg signed [11:0] p);
wire [5:0] q0={~(a[0]&b[5]),({5{a[0]}}&b[4:0])};
wire [5:0] q1={~(a[1]&b[5]),({5{a[1]}}&b[4:0])};
wire [5:0] q2={~(a[2]&b[5]),({5{a[2]}}&b[4:0])};
wire [5:0] q3={~(a[3]&b[5]),({5{a[3]}}&b[4:0])};
wire [5:0] q4={~(a[4]&b[5]),({5{a[4]}}&b[4:0])};
wire [11:0] r0={6'd0,q0}|12'h840,r1={5'd0,q1,1'b0},r2={4'd0,q2,2'b0};
wire [11:0] r3={3'd0,q3,3'b0},r4={2'd0,q4,4'b0};
wire [11:0] r5={1'b0,(a[5]&b[5]),~({5{a[5]}}&b[4:0]),5'd0};
wire [11:0] s0=r0^r1^r2,c0=((r0&r1)|(r0&r2)|(r1&r2))<<1;
wire [11:0] s1=r3^r4^r5,c1=((r3&r4)|(r3&r5)|(r4&r5))<<1;
wire [11:0] s2=s0^c0^s1,c2=((s0&c0)|(s0&s1)|(c0&s1))<<1;
wire [11:0] s3=s2^c2^c1,c3=((s2&c2)|(s2&c1)|(c2&c1))<<1;
always @(posedge clk)if(rst)p<=0;else p<=s3+c3;
endmodule

// Unsigned registered product; native tests use the installed vendor model.
module photo_relief_remote_lighting_product(input clk,rst,input [17:0] a,input [7:0] b,output [25:0] p);
`ifdef RELIEF_SIM
`ifdef RELIEF_NATIVE_DSP
localparam NATIVE=1;
`else
localparam NATIVE=0;
`endif
`else
localparam NATIVE=1;
`endif
generate if(NATIVE)begin:native
 wire [35:0] wide;
 EG_PHY_MULT18 #(.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),
  .OUTPUTREG("ENABLE"),.SRMODE("SYNC")) multiply(
  .a(a),.b({10'd0,b}),.p(wide),.signeda(1'b0),.signedb(1'b0),
  .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
  .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(clk),.rstan(1'b1),.rstbn(1'b1),.rstpdn(!rst));
 assign p=wide[25:0];
end else begin:simulation
 reg [25:0] product;
 always @(posedge clk)if(rst)product<=0;else product<=a*b;
 assign p=product;
end endgenerate
endmodule

module photo_relief_row_cache(input wc,we,input [11:0] wa,input [7:0] wd,
 input rc,input [11:0] ra,output [7:0] rd);
wire [7:0] q0,q1,q2;reg [1:0] bank;
always @(posedge rc)bank<=ra[9:8];
assign rd=bank==0 ? q0:bank==1 ? q1:q2;
photo_relief_ram #(.DATA_BITS(8),.ADDRESS_BITS(10),.DEPTH(1024)) b0(
 .wc(wc),.we(we && wa[9:8]==0),.wa({wa[11:10],wa[7:0]}),.wd(wd),.rc(rc),.ra({ra[11:10],ra[7:0]}),.rd(q0));
photo_relief_ram #(.DATA_BITS(8),.ADDRESS_BITS(10),.DEPTH(1024)) b1(
 .wc(wc),.we(we && wa[9:8]==1),.wa({wa[11:10],wa[7:0]}),.wd(wd),.rc(rc),.ra({ra[11:10],ra[7:0]}),.rd(q1));
photo_relief_ram #(.DATA_BITS(8),.ADDRESS_BITS(10),.DEPTH(1024)) b2(
 .wc(wc),.we(we && wa[9:8]==2),.wa({wa[11:10],wa[7:0]}),.wd(wd),.rc(rc),.ra({ra[11:10],ra[7:0]}),.rd(q2));
endmodule

// Four tiny 16x8 distributed memories retain one sixteen-word response.
// The read is asynchronous; row expansion consumes one byte per memory clock.
module photo_relief_burst_cache(input clk,we,input [5:0] wa,input [31:0] wd,
 input [7:0] ra,output [7:0] rd);
wire [31:0] q;
`ifdef RELIEF_SIM
reg [31:0] memory[0:63];always @(posedge clk)if(we)memory[wa]<=wd;
assign q=memory[ra[7:2]];
`else
EG_LOGIC_DRAM #(.DATA_WIDTH_W(32),.DATA_WIDTH_R(32),.ADDR_WIDTH_W(6),.ADDR_WIDTH_R(6),
 .DATA_DEPTH_W(64),.DATA_DEPTH_R(64)) memory(.di(wd),.waddr(wa),.we(we),.wclk(clk),.raddr(ra[7:2]),.do(q));
`endif
assign rd=q>>(ra[1:0]*8);
endmodule

// Retain all four descriptors from a directory burst. Sequential row jobs
// reuse the other three entries without taking another SDRAM turn.
module photo_relief_directory_cache(input clk,we,input [1:0] wa,input [31:0] wd,
 input [1:0] ra,output [31:0] rd);
`ifdef RELIEF_SIM
reg [31:0] memory[0:3];always @(posedge clk)if(we)memory[wa]<=wd;
assign rd=memory[ra];
`else
EG_LOGIC_DRAM #(.DATA_WIDTH_W(32),.DATA_WIDTH_R(32),.ADDR_WIDTH_W(2),.ADDR_WIDTH_R(2),
 .DATA_DEPTH_W(4),.DATA_DEPTH_R(4)) memory(.di(wd),.waddr(wa),.we(we),.wclk(clk),.raddr(ra),.do(rd));
`endif
endmodule
