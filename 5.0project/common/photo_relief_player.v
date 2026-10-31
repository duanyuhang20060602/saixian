// SXDLT008: 24 independent palettes and sparse 576x576 surface views.
// A shared palette and four decoded rows retain native surface details. Wall
// normals arrive in the existing framebuffer. Input-to-output latency: 12.
module photo_relief_player #(parameter HOLD_FRAMES=10,SHARED_PALETTE=0,REMOTE_RELIEF=0,SHARED_MATH=0)(
 input mem_clk,mem_rst,enable,input [20:0] base,
 output wide_request,output reg request,output [20:0] address,input ack,
 input [31:0] data,input valid,
 input clk,rst,pause,frame_tick,de,input [10:0] x,input [9:0] y,
 input [23:0] rgb_in,input touch_contact,input [10:0] cursor_x,input [9:0] cursor_y,
 output [23:0] rgb_out,output [3:0] error,output [4:0] angle,
 output cache_write_en,output [7:0] cache_write_address,output [31:0] cache_write_data,
 output [7:0] cache_read_address,input [31:0] cache_read_data,
 input remote_valid,input [4:0] remote_angle,input signed [5:0] remote_light_x,remote_light_y,
 output [4:0] desired_angle,output signed [5:0] desired_light_x,desired_light_y,
 output [6:0] wall_address,input [23:0] wall_rgb,
 output signed [5:0] math_nx,math_ny,math_lx,math_ly,
 input signed [14:0] math_product_x,math_product_y
);
wire signed [5:0] light_x=REMOTE_RELIEF ? remote_light_x:desired_light_x;
wire signed [5:0] light_y=REMOTE_RELIEF ? remote_light_y:desired_light_y;
assign angle=REMOTE_RELIEF ? remote_angle:desired_angle;
assign math_lx=light_x;assign math_ly=light_y;
wire frame_update;
photo_relief_motion #(.HOLD_FRAMES(HOLD_FRAMES)) motion(.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(frame_tick),
 .touch_contact(touch_contact),.cursor_x(cursor_x),.cursor_y(cursor_y),
 .angle(desired_angle),.light_x(desired_light_x),.light_y(desired_light_y),.frame_update(frame_update));

reg request_toggle;reg [4:0] requested_angle;reg [9:0] requested_row;
(* async_reg="true" *)reg enable_meta,enable_sync;
(* async_reg="true" *)reg [2:0] request_sync;
(* async_reg="true" *)reg [4:0] angle_meta;reg [4:0] angle_sync;
(* async_reg="true" *)reg [9:0] row_meta;reg [9:0] row_sync;
reg done_toggle,palette_ready,seen,palette_loaded;reg [4:0] loaded_angle;
localparam IDLE=0,ASK=1,READ=2,DIRECTORY=3,DECODE=4,DIR_START=5,DIR_CACHED=6,CACHE_WAIT=7;
localparam PALETTE=0,ROW_DIRECTORY=1,ROW_STREAM=2;
reg [2:0] state;reg [1:0] job;reg [5:0] lane;reg [7:0] position;
reg [4:0] job_angle;reg [9:0] job_row,column;
reg [20:0] burst_address;reg [14:0] directory_offset;
assign address=burst_address;reg [31:0] descriptor;
reg [8:0] byte_number;reg [7:0] initial_byte;reg [10:0] encoded_left;
reg need_run_value;reg [7:0] run_left,literal_left,run_value;reg [3:0] mem_error;
reg dir_valid;reg [4:0] dir_angle;reg [7:0] dir_group;
wire [31:0] cached_descriptor;
wire row_we;
wire [7:0] code;
assign wide_request=job!=ROW_DIRECTORY;
generate if(!REMOTE_RELIEF)begin:local_decode_cache
photo_relief_directory_cache dir_cache(.clk(mem_clk),.we(state==READ && valid && job==ROW_DIRECTORY),
 .wa(lane[1:0]),.wd(data),.ra(job_row[1:0]),.rd(cached_descriptor));
photo_relief_burst_cache burst_cache(.clk(mem_clk),.we(state==READ && valid && job==ROW_STREAM),
 .wa(lane),.wd(data),.ra(byte_number[7:0]),.rd(code));
end else begin:compact_decode_cache
 wire [7:0] future_byte=byte_number[7:0]+(state==DECODE && byte_number<256 && encoded_left!=0 &&
  (!row_we || (literal_left!=0 && run_left==0)));
 wire [6:0] read_word=job==ROW_DIRECTORY ? {5'b10000,job_row[1:0]}:{1'b0,future_byte[7:2]};
 wire [31:0] q;reg [1:0] byte_lane;
 always @(posedge mem_clk)byte_lane<=future_byte[1:0];
 photo_relief_decode_cache memory(.clk(mem_clk),.we(state==READ && valid && job!=PALETTE),
  .wa(job==ROW_DIRECTORY ? {5'b10000,lane[1:0]}:{1'b0,lane}),.wd(data),.ra(read_word),.rd(q));
 assign cached_descriptor=q;assign code=q>>(byte_lane*8);
end endgenerate
wire implicit_zero=encoded_left==0 && run_left==0 && literal_left==0 && !need_run_value;
assign row_we=enable_sync && state==DECODE && !need_run_value &&
 (implicit_zero || run_left!=0 || (literal_left!=0 && encoded_left!=0 && byte_number<256));
wire [7:0] row_data=implicit_zero ? 8'd0:run_left!=0 ? run_value:code;
always @(posedge mem_clk or posedge mem_rst)
 if(mem_rst)begin enable_meta<=0;enable_sync<=0;end
 else begin enable_meta<=enable;enable_sync<=enable_meta;end
always @(posedge mem_clk)begin
 request_sync<={request_sync[1:0],request_toggle};
 angle_meta<=requested_angle;angle_sync<=angle_meta;row_meta<=requested_row;row_sync<=row_meta;
 if(mem_rst || !enable_sync)begin
  request_sync<=0;angle_meta<=0;angle_sync<=0;row_meta<=0;row_sync<=0;
  done_toggle<=0;palette_ready<=0;palette_loaded<=0;loaded_angle<=0;seen<=0;
  state<=IDLE;request<=0;burst_address<=0;directory_offset<=0;dir_valid<=0;dir_angle<=0;dir_group<=0;job<=PALETTE;lane<=0;position<=0;
  job_angle<=0;job_row<=0;column<=0;descriptor<=0;byte_number<=0;initial_byte<=0;
  encoded_left<=0;need_run_value<=0;run_left<=0;literal_left<=0;run_value<=0;mem_error<=0;
 end else case(state)
 IDLE:if(request_sync[2]!=seen && mem_error==0)begin
  seen<=request_sync[2];job_angle<=angle_sync;job_row<=row_sync;column<=0;
  directory_offset<=15'd6208+({10'd0,angle_sync}<<9)+({10'd0,angle_sync}<<6)+{5'd0,row_sync[9:2],2'b00};
  need_run_value<=0;run_left<=0;literal_left<=0;run_value<=0;position<=0;
  if(!REMOTE_RELIEF && (!palette_loaded || loaded_angle!=angle_sync))begin
   palette_ready<=0;job<=PALETTE;burst_address<=base+{8'd0,angle_sync,8'h40};state<=ASK;
  end else begin palette_ready<=1;job<=ROW_DIRECTORY;state<=(dir_valid && dir_angle==angle_sync && dir_group==row_sync[9:2]) ? (REMOTE_RELIEF ? CACHE_WAIT:DIR_CACHED):DIR_START;end
 end
 CACHE_WAIT:state<=job==ROW_STREAM ? DECODE:DIR_CACHED;
 DIR_CACHED:begin descriptor<=cached_descriptor;state<=DIRECTORY;end
 DIR_START:begin burst_address<=base+{6'd0,directory_offset};state<=ASK;end
 ASK:begin request<=1;if(ack)begin request<=0;lane<=0;state<=READ;end end
 READ:if(valid)begin
  lane<=lane+1'b1;
  if(!REMOTE_RELIEF && job==PALETTE)position<=position+1'b1;
  if(job==ROW_DIRECTORY && lane==job_row[1:0])descriptor<=data;
    if(lane==(job==ROW_DIRECTORY ? 3:63))begin
   if(!REMOTE_RELIEF && job==PALETTE)begin
    if(position==255)begin
     palette_ready<=1;palette_loaded<=1;loaded_angle<=job_angle;job<=ROW_DIRECTORY;state<=DIR_START;
    end else begin burst_address<=burst_address+64;state<=ASK;end
   end else if(job==ROW_DIRECTORY)begin dir_valid<=1;dir_angle<=job_angle;dir_group<=job_row[9:2];state<=DIRECTORY;end
   else begin byte_number<={1'b0,initial_byte};initial_byte<=0;state<=REMOTE_RELIEF ? CACHE_WAIT:DECODE;end
  end
 end
 DIRECTORY:begin
  encoded_left<=descriptor[31:21];initial_byte<=descriptor[7:0];byte_number<=0;
  if(descriptor[31:21]>768 || descriptor[20:0]<80128 ||
     {1'b0,descriptor[20:0]}+{11'd0,descriptor[31:21]}>22'd2097152)begin mem_error<=4;state<=IDLE;end
  else if(descriptor[31:21]==0)state<=DECODE;
  else begin job<=ROW_STREAM;burst_address<=base+{2'd0,descriptor[20:8],6'b000000};state<=ASK;end
 end
 DECODE:begin
  if(row_we)begin
   column<=column+1'b1;
   if(run_left!=0)run_left<=run_left-1'b1;
   else if(literal_left!=0)begin literal_left<=literal_left-1'b1;byte_number<=byte_number+1'b1;encoded_left<=encoded_left-1'b1;end
   if(column==575)begin
    if(need_run_value || run_left>1 || literal_left>1 || encoded_left>(literal_left!=0 ? 1:0))mem_error<=5;
    done_toggle<=seen;state<=IDLE;
   end
  end else if(byte_number==256)begin byte_number<=0;burst_address<=burst_address+64;state<=ASK;end
  else if(encoded_left==0)begin mem_error<=6;state<=IDLE;end
  else begin
   byte_number<=byte_number+1'b1;encoded_left<=encoded_left-1'b1;
   if(need_run_value)begin need_run_value<=0;run_value<=code;end
   else if(code[7])begin run_left<={1'b0,code[6:0]}+8'd1;need_run_value<=1;end
   else literal_left<={1'b0,code[6:0]}+8'd1;
  end
 end
 default:state<=IDLE;
 endcase
end
wire palette_we=enable_sync && state==READ && valid && job==PALETTE;
(* async_reg="true" *)reg [2:0] done_sync,ready_sync;
(* async_reg="true" *)reg [3:0] mem_error_meta,mem_error_sync;
reg pending,started;reg [3:0] row_valid;
reg [2:0] prefetch_count;
reg [9:0] source_row,source_column,next_prefetch_row;
wire source_advance=x==0 && y>48 && y<624;
wire launch_row=started && !pending && next_prefetch_row<576 && prefetch_count<4;
reg [3:0] video_error;
assign error=video_error | mem_error_sync;
wire in_sprite=de && x>=352 && x<928 && y>=48 && y<624;
wire row_good=row_valid[source_row[1:0]];
always @(posedge clk)begin
 done_sync<={done_sync[1:0],done_toggle};ready_sync<={ready_sync[1:0],palette_ready};
 mem_error_meta<=mem_error;mem_error_sync<=mem_error_meta;
 if(rst || !enable)begin
  done_sync<=0;ready_sync<=0;mem_error_meta<=0;mem_error_sync<=0;
  pending<=0;started<=0;request_toggle<=0;requested_angle<=0;requested_row<=0;
  row_valid<=0;prefetch_count<=0;
  source_row<=0;source_column<=0;video_error<=0;next_prefetch_row<=0;
 end else begin
  if(pending && done_sync[2]==request_toggle)begin
   pending<=0;row_valid[requested_row[1:0]]<=1;
  end
  // Retire consumed rows before their ring slots can be reused. A live
  // validity bit therefore cannot refer to the preceding eight-row window.
  if(source_advance)row_valid[source_row[1:0]]<=0;
  case({launch_row,source_advance})
   2'b10:prefetch_count<=prefetch_count+1'b1;
   2'b01:prefetch_count<=prefetch_count-1'b1;
   default:begin end
  endcase
  // The 576 source pixels map one-to-one to the displayed cup footprint.
  if(!in_sprite)source_column<=0;else source_column<=source_column+1'b1;
  if(x==0)begin
   if(y<=48)source_row<=0;
   else if(y<624)source_row<=source_row+1'b1;
  end
  if(frame_update)begin
   started<=1;source_row<=0;
   if(pending)video_error<=1;
   else begin
    requested_angle<=angle;requested_row<=0;request_toggle<=~request_toggle;
    pending<=1;row_valid<=0;next_prefetch_row<=1;prefetch_count<=1;
   end
  end else if(launch_row)begin
   requested_row<=next_prefetch_row;request_toggle<=~request_toggle;pending<=1;
   row_valid[next_prefetch_row[1:0]]<=0;next_prefetch_row<=next_prefetch_row+1'b1;
  end
  if(started && de && x==352 && y>=48 && y<624 && ready_sync[2] && !row_good)video_error<=3;
 end
end
wire [7:0] row_word;wire [31:0] palette_word;reg [7:0] token;
reg [2:0] inside_pipe;reg [15:0] bg0,bg1,bg2;
wire [15:0] raw={rgb_in[23:19],rgb_in[15:10],rgb_in[7:3]};
// Four 576-byte rows share three 9K blocks in 256-pixel column strips.
// Column-bank addressing avoids wide row-address additions.
wire [11:0] write_row_address={job_row[1:0],column};
wire [11:0] read_row_address={source_row[1:0],source_column};
photo_relief_row_cache rows(.wc(mem_clk),.we(row_we),.wa(write_row_address),.wd(row_data),
 .rc(clk),.ra(read_row_address),.rd(row_word));
assign cache_write_en=palette_we;assign cache_write_address=position;assign cache_write_data=data;
assign cache_read_address=token;
generate if(!SHARED_PALETTE)begin:private_palette
 photo_relief_ram #(.ADDRESS_BITS(8),.DEPTH(256)) palette(
 .wc(mem_clk),.we(palette_we),.wa(position),.wd(data),.rc(clk),.ra(token),.rd(palette_word));
end else begin:external_palette
 assign palette_word=cache_read_data;
end endgenerate
always @(posedge clk)begin
 token<=row_word;bg0<=raw;bg1<=bg0;bg2<=bg1;
 inside_pipe<={inside_pipe[1:0],in_sprite && row_good && ready_sync[2] && enable};
 if(rst)begin inside_pipe<=0;token<=0;bg0<=0;bg1<=0;bg2<=0;end
end
wire cup=inside_pipe[2] && palette_word[0];
wire [15:0] surface=cup ? palette_word[15:0]:bg2;
wire [15:0] base_color=cup ? palette_word[31:16]:bg2;
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
generate if(!REMOTE_RELIEF)begin:local_lighting
assign wall_address=0;assign math_nx=0;assign math_ny=0;
reg signed [5:0] nx,ny;reg [4:0] nz;
reg [23:0] color3,color4,color5,color6;
reg [3:0] wall_pipe,cup_pipe;
wire signed [11:0] px,py;reg [9:0] pz;
photo_relief_product product_x(.clk(clk),.rst(rst),.a(nx),.b(light_x),.p(px));
photo_relief_product product_y(.clk(clk),.rst(rst),.a(ny),.b(light_y),.p(py));
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
photo_relief_lighting_product diffuse_rb(.clk(clk),.rst(rst),
 .a({color6[23:19],8'd0,color6[7:3]}),.b(diffuse),.p(packed_diffuse));
photo_relief_lighting_product diffuse_g(.clk(clk),.rst(rst),
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
 color3<=expand(base_color);wall_pipe<={wall_pipe[2:0],!cup && bg2[0]};cup_pipe<={cup_pipe[2:0],cup};
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
 wall7<=wall_pipe[3];wall_diffuse7<=diffuse[7:1];
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
assign rgb_out=delay11;
end else begin:remote_lighting
 reg signed [5:0] nx,ny;reg [4:0] nz;wire signed [11:0] px,py;
 reg [9:0] pz;reg signed [12:0] dot;reg [7:0] diffuse;
 reg [23:0] c3,c4,c5,c6,c7,c8,c9,c10,c11;
 reg [3:0] walls,cups;reg wall7,cup7;
 assign math_nx=nx;assign math_ny=ny;
 if(SHARED_MATH)begin:shared_products
  assign px=math_product_x[11:0];assign py=math_product_y[11:0];
 end else begin:private_products
  photo_relief_wall_dsp_product mx(.clk(clk),.rst(rst),.a(nx),.b(light_x),.p(px));
  photo_relief_wall_dsp_product my(.clk(clk),.rst(rst),.a(ny),.b(light_y),.p(py));
 end
 assign wall_address=diffuse[7:1];
 // Only fixed RGB565 fallback text needs a local exposure conversion.
 // Cup RGB and the 128 wall response values already arrive exposed from B.
function [7:0] exposure_rb5;input [4:0] v;begin case(v)
5'd0:exposure_rb5=8'd0;
5'd1:exposure_rb5=8'd16;
5'd2:exposure_rb5=8'd30;
5'd3:exposure_rb5=8'd44;
5'd4:exposure_rb5=8'd58;
5'd5:exposure_rb5=8'd71;
5'd6:exposure_rb5=8'd82;
5'd7:exposure_rb5=8'd93;
5'd8:exposure_rb5=8'd105;
5'd9:exposure_rb5=8'd115;
5'd10:exposure_rb5=8'd124;
5'd11:exposure_rb5=8'd133;
5'd12:exposure_rb5=8'd143;
5'd13:exposure_rb5=8'd151;
5'd14:exposure_rb5=8'd159;
5'd15:exposure_rb5=8'd166;
5'd16:exposure_rb5=8'd174;
5'd17:exposure_rb5=8'd181;
5'd18:exposure_rb5=8'd187;
5'd19:exposure_rb5=8'd194;
5'd20:exposure_rb5=8'd200;
5'd21:exposure_rb5=8'd206;
5'd22:exposure_rb5=8'd212;
5'd23:exposure_rb5=8'd217;
5'd24:exposure_rb5=8'd223;
5'd25:exposure_rb5=8'd228;
5'd26:exposure_rb5=8'd233;
5'd27:exposure_rb5=8'd237;
5'd28:exposure_rb5=8'd242;
5'd29:exposure_rb5=8'd247;
5'd30:exposure_rb5=8'd251;
5'd31:exposure_rb5=8'd255;
endcase end endfunction
function [7:0] exposure_g6;input [5:0] v;begin case(v)
6'd0:exposure_g6=8'd0;
6'd1:exposure_g6=8'd8;
6'd2:exposure_g6=8'd16;
6'd3:exposure_g6=8'd23;
6'd4:exposure_g6=8'd30;
6'd5:exposure_g6=8'd37;
6'd6:exposure_g6=8'd44;
6'd7:exposure_g6=8'd50;
6'd8:exposure_g6=8'd57;
6'd9:exposure_g6=8'd63;
6'd10:exposure_g6=8'd69;
6'd11:exposure_g6=8'd75;
6'd12:exposure_g6=8'd81;
6'd13:exposure_g6=8'd86;
6'd14:exposure_g6=8'd92;
6'd15:exposure_g6=8'd97;
6'd16:exposure_g6=8'd104;
6'd17:exposure_g6=8'd109;
6'd18:exposure_g6=8'd114;
6'd19:exposure_g6=8'd118;
6'd20:exposure_g6=8'd123;
6'd21:exposure_g6=8'd128;
6'd22:exposure_g6=8'd132;
6'd23:exposure_g6=8'd136;
6'd24:exposure_g6=8'd141;
6'd25:exposure_g6=8'd145;
6'd26:exposure_g6=8'd149;
6'd27:exposure_g6=8'd153;
6'd28:exposure_g6=8'd157;
6'd29:exposure_g6=8'd160;
6'd30:exposure_g6=8'd164;
6'd31:exposure_g6=8'd168;
6'd32:exposure_g6=8'd172;
6'd33:exposure_g6=8'd176;
6'd34:exposure_g6=8'd179;
6'd35:exposure_g6=8'd182;
6'd36:exposure_g6=8'd186;
6'd37:exposure_g6=8'd189;
6'd38:exposure_g6=8'd192;
6'd39:exposure_g6=8'd195;
6'd40:exposure_g6=8'd198;
6'd41:exposure_g6=8'd201;
6'd42:exposure_g6=8'd204;
6'd43:exposure_g6=8'd207;
6'd44:exposure_g6=8'd210;
6'd45:exposure_g6=8'd212;
6'd46:exposure_g6=8'd215;
6'd47:exposure_g6=8'd218;
6'd48:exposure_g6=8'd221;
6'd49:exposure_g6=8'd224;
6'd50:exposure_g6=8'd226;
6'd51:exposure_g6=8'd229;
6'd52:exposure_g6=8'd231;
6'd53:exposure_g6=8'd233;
6'd54:exposure_g6=8'd236;
6'd55:exposure_g6=8'd238;
6'd56:exposure_g6=8'd240;
6'd57:exposure_g6=8'd242;
6'd58:exposure_g6=8'd245;
6'd59:exposure_g6=8'd247;
6'd60:exposure_g6=8'd249;
6'd61:exposure_g6=8'd251;
6'd62:exposure_g6=8'd253;
6'd63:exposure_g6=8'd255;
endcase end endfunction

 always @(posedge clk)begin
  nx<=$signed({bg2[15:11],1'b0});ny<=$signed({bg2[10:6],1'b0});nz<=bg2[5:1];
  c3<=cup ? palette_word[31:8]:{exposure_rb5(bg2[15:11]),exposure_g6(bg2[10:5]),exposure_rb5(bg2[4:0])};
  walls<={walls[2:0],!cup && bg2[0]};cups<={cups[2:0],cup};
  pz<={nz,4'b0};c4<=c3;
  dot<=$signed({px[11],px})+$signed({py[11],py})+$signed({3'b0,pz});c5<=c4;
  diffuse<=dot<0 ? 0:dot>1020 ? 255:dot[9:2];c6<=c5;
  c7<=c6;wall7<=walls[3];cup7<=cups[3];
  c8<=wall7 && !cup7 ? wall_rgb:c7;
  c9<=c8;c10<=c9;c11<=remote_valid ? c10:24'h6d4825;
  if(rst)begin nx<=0;ny<=0;nz<=0;pz<=0;dot<=0;diffuse<=0;walls<=0;cups<=0;wall7<=0;cup7<=0;
   c3<=0;c4<=0;c5<=0;c6<=0;c7<=0;c8<=0;c9<=0;c10<=0;c11<=0;end
 end
 assign rgb_out=c11;
end endgenerate
endmodule

module photo_relief_ram #(parameter DATA_BITS=32,ADDRESS_BITS=8,DEPTH=256)(
 input wc,we,input [ADDRESS_BITS-1:0] wa,input [DATA_BITS-1:0] wd,
 input rc,input [ADDRESS_BITS-1:0] ra,output [DATA_BITS-1:0] rd
);
`ifdef RELIEF_SIM
reg [DATA_BITS-1:0] memory[0:DEPTH-1];reg [DATA_BITS-1:0] q;
always @(posedge wc)if(we)memory[wa]<=wd;
always @(posedge rc)q<=memory[ra];
assign rd=q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(DATA_BITS),.ADDR_WIDTH_A(ADDRESS_BITS),.DATA_DEPTH_A(DEPTH),
 .DATA_WIDTH_B(DATA_BITS),.ADDR_WIDTH_B(ADDRESS_BITS),.DATA_DEPTH_B(DEPTH),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),
 .WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) memory(
 .clka(wc),.rsta(1'b0),.cea(1'b1),.wea(we),.ocea(1'b1),.bea(1'b0),.addra(wa),.dia(wd),.doa(),
 .clkb(rc),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(ra),.dib({DATA_BITS{1'b0}}),.dob(rd));
`endif
endmodule


// Signed 6x6 Baugh-Wooley array. All arithmetic is modulo 2^12; inverted
// sign-column products are corrected by constant bits 11 and 6 in row zero.
// Carry-save reduction leaves one carry-propagate adder before the register.
// No multiplier operator or DSP primitive is used for these small products.
module photo_relief_product(input clk,rst,input signed [5:0] a,b,output reg signed [11:0] p);
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
module photo_relief_lighting_product(input clk,rst,input [17:0] a,input [7:0] b,output [25:0] p);
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

module photo_relief_wall_dsp_product(input clk,rst,input signed [5:0] a,b,output signed [11:0] p);
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
  .a({{12{a[5]}},a}),.b({{12{b[5]}},b}),.p(wide),.signeda(1'b0),.signedb(1'b0),
  .acin(18'd0),.bcin(18'd0),.sourcea(1'b1),.sourceb(1'b1),.acout(),.bcout(),
  .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.clk(clk),.rstan(1'b1),.rstbn(1'b1),.rstpdn(!rst));
 assign p=wide[11:0];
end else begin:simulation
 reg signed [11:0] product;
 always @(posedge clk)if(rst)product<=0;else product<=a*b;
 assign p=product;
end endgenerate
endmodule

