// Input follows frame_pixels (two clocks from the raster). The original
// award effect takes five clocks; nineteen more align with HDMI's 26 clocks.
module photo_award_render #(parameter RELIEF_ENABLE=0,SHARED_ENABLE=1)(
 input relief_mode,touch_contact,input [10:0] cursor_x,input [9:0] cursor_y,
 input mem_clk,mem_rst,input [20:0] light_base,
 output light_wide,output light_request,output [20:0] light_address,input light_ack,input [31:0] light_data,input light_valid,
 input de_in,input clk,rst,enable,pause,frame_tick,
 input [10:0] x,input [9:0] y,input [23:0] tagged_rgb,
 output [23:0] rgb,output [23:0] menu_rgb,
 output [3:0] light_error,output [6:0] light_frame
);
wire relief=RELIEF_ENABLE && relief_mode;
// Mode originates in the pixel clock. SDRAM routing and response enables
// must use its memory-clock copy, just like each player's enable input.
(* async_reg="true" *)reg relief_meta,relief_mem;
reg route_d,burst_relief;
always @(posedge mem_clk or posedge mem_rst)
 if(mem_rst)begin relief_meta<=0;relief_mem<=0;route_d<=0;burst_relief<=0;end
 else begin
  relief_meta<=relief;relief_mem<=relief_meta;route_d<=relief_mem;
  // The arbiter registers ACK. Retain that grant's owner until all four
  // response words return, even if the visible mode changes meanwhile.
  if(light_ack)burst_relief<=route_d;
 end
wire old_request;wire [20:0] old_address;wire [3:0] old_error;wire [6:0] old_frame;
wire new_request,new_wide;wire [20:0] new_address;wire [3:0] new_error;wire [4:0] new_frame;wire [23:0] new_rgb;
assign light_wide=relief_mem && new_wide;
assign light_request=relief_mem ? new_request:old_request;
assign light_address=relief_mem ? new_address:old_address;
assign light_error=relief ? new_error:old_error;
assign light_frame=relief ? {2'd0,new_frame}:old_frame;
// The two award modes are mutually exclusive. Reuse the old 512x32 row
// cache for the new 256x32 material palette, with the same synchronous read.
wire old_cache_we,new_cache_we;wire [8:0] old_cache_wa,old_cache_ra;
wire [7:0] new_cache_wa,new_cache_ra;wire [31:0] old_cache_wd,new_cache_wd,shared_cache_data;
generate if(RELIEF_ENABLE && SHARED_ENABLE)begin:shared_award_cache
 photo_relief_ram #(.ADDRESS_BITS(9),.DEPTH(512)) memory(
 .wc(mem_clk),.we(relief_mem ? new_cache_we:old_cache_we),
 .wa(relief_mem ? {1'b0,new_cache_wa}:old_cache_wa),.wd(relief_mem ? new_cache_wd:old_cache_wd),
 .rc(clk),.ra(relief ? {1'b0,new_cache_ra}:old_cache_ra),.rd(shared_cache_data));
end else begin
 assign shared_cache_data=0;
end endgenerate
generate if(RELIEF_ENABLE)begin:gold
 photo_relief_player #(.SHARED_PALETTE(SHARED_ENABLE)) player(.mem_clk(mem_clk),.mem_rst(mem_rst),.enable(enable && relief),.base(light_base),
 .wide_request(new_wide),.request(new_request),.address(new_address),.ack(light_ack && route_d),.data(light_data),.valid(light_valid && burst_relief),
 .clk(clk),.rst(rst),.pause(pause),.frame_tick(frame_tick),.de(de_in),.x(x),.y(y),.rgb_in(tagged_rgb),
 .touch_contact(touch_contact),.cursor_x(cursor_x),.cursor_y(cursor_y),.rgb_out(new_rgb),.error(new_error),.angle(new_frame),
 .cache_write_en(new_cache_we),.cache_write_address(new_cache_wa),.cache_write_data(new_cache_wd),
 .cache_read_address(new_cache_ra),.cache_read_data(shared_cache_data));
end else begin
 assign new_cache_we=0;assign new_cache_wa=0;assign new_cache_wd=0;assign new_cache_ra=0;
 assign new_wide=0;assign new_request=0;assign new_address=0;assign new_error=0;assign new_frame=0;assign new_rgb=0;
end endgenerate
wire [15:0] pixel={tagged_rgb[23:19],tagged_rgb[15:10],tagged_rgb[7:3]};
wire [4:0] blue=pixel[0] ? {1'b0,pixel[10:7]} : {pixel[4:1],1'b0};
wire [5:0] green=pixel[0] ? {pixel[10:6],1'b0} : pixel[10:5];
wire [23:0] base={pixel[15:11],pixel[15:13],green,green[5:4],blue,blue[4:2]};
wire [23:0] effect_rgb;
award_fx #(.INITIAL_HOLD_FRAMES(0)) effect(.clk(clk),.rst(rst),.enable(enable && !relief),.pause(pause),.frame_tick(frame_tick),
 .x(x),.y(y),.base_rgb(base),.tag(pixel[5:0]),.rgb(effect_rgb));
wire [23:0] light_rgb;
reg [4:0] light_de,light_vs;
always @(posedge clk)if(rst)begin light_de<=0;light_vs<=0;end
 else begin light_de<={light_de[3:0],de_in};light_vs<={light_vs[3:0],frame_tick};end
photo_spotlight_player #(.SHARED_CACHE(RELIEF_ENABLE && SHARED_ENABLE)) lights(.mem_clk(mem_clk),.mem_rst(mem_rst),.enable(enable && !relief),.base(light_base),
 .stream_start(old_request),.stream_offset(old_address),.stream_ack(light_ack && !route_d),.data(light_data),.data_valid(light_valid && !burst_relief),.error(old_error),
 .video_clk(clk),.video_rst(rst || !enable || relief),.display_valid(enable),.pause(pause),
 .rgb_in(effect_rgb),.de_in(light_de[4]),.vs_in(light_vs[4]),.rgb_out(light_rgb),.de_out(),.vs_out(),.frame_index(old_frame),.initialized(),
 .cache_write_en(old_cache_we),.cache_write_address(old_cache_wa),.cache_write_data(old_cache_wd),
 .cache_read_address(old_cache_ra),.cache_read_data(shared_cache_data));
photo_award_delay video_delay(.clk(clk),.rst(rst),.rgb_in(relief ? new_rgb:light_rgb),.rgb(rgb),.menu_rgb(menu_rgb));
endmodule

// Coordinates and RGB arrive together at the existing 21-cycle menu tap.
// The small combinational banner adds no video latency or font RAM.
module photo_award_notice(input clk,rst,input [2:0] notice,input [11:0] x,input [10:0] y,
 input [23:0] rgb_in,output [23:0] rgb_out);
reg notice_visible;
wire box=notice_visible && x>=16 && x<280 && y>=16 && y<48;
wire letters=x>=24 && x<264 && y>=22 && y<36;
wire [11:0] dx=x-24;wire [10:0] dy=y-22;
reg [2:0] notice_code;reg [7:0] ch;reg [34:0] glyph;reg ink;
// The message has only four fixed alternatives. Select the character
// directly; a 120-bit variable barrel shift is unnecessary on every pixel.
function [7:0] notice_character;input[2:0] code;input[3:0] position;begin
 notice_character=0;
 case(code)
 1:case(position)
  0:notice_character=8'h41;
  1:notice_character=8'h57;
  2:notice_character=8'h41;
  3:notice_character=8'h52;
  4:notice_character=8'h44;
  5:notice_character=8'h20;
  6:notice_character=8'h4c;
  7:notice_character=8'h4f;
  8:notice_character=8'h41;
  9:notice_character=8'h44;
  10:notice_character=8'h49;
  11:notice_character=8'h4e;
  12:notice_character=8'h47;
  13:notice_character=8'h20;
  14:notice_character=8'h20;
  default:notice_character=0;
 endcase
 2:case(position)
  0:notice_character=8'h41;
  1:notice_character=8'h57;
  2:notice_character=8'h41;
  3:notice_character=8'h52;
  4:notice_character=8'h44;
  5:notice_character=8'h20;
  6:notice_character=8'h4e;
  7:notice_character=8'h4f;
  8:notice_character=8'h54;
  9:notice_character=8'h20;
  10:notice_character=8'h46;
  11:notice_character=8'h4f;
  12:notice_character=8'h55;
  13:notice_character=8'h4e;
  14:notice_character=8'h44;
  default:notice_character=0;
 endcase
 3:case(position)
  0:notice_character=8'h41;
  1:notice_character=8'h57;
  2:notice_character=8'h41;
  3:notice_character=8'h52;
  4:notice_character=8'h44;
  5:notice_character=8'h20;
  6:notice_character=8'h45;
  7:notice_character=8'h52;
  8:notice_character=8'h52;
  9:notice_character=8'h4f;
  10:notice_character=8'h52;
  11:notice_character=8'h20;
  12:notice_character=8'h20;
  13:notice_character=8'h20;
  14:notice_character=8'h20;
  default:notice_character=0;
 endcase
 4:case(position)
  0:notice_character=8'h50;
  1:notice_character=8'h48;
  2:notice_character=8'h4f;
  3:notice_character=8'h54;
  4:notice_character=8'h4f;
  5:notice_character=8'h20;
  6:notice_character=8'h45;
  7:notice_character=8'h52;
  8:notice_character=8'h52;
  9:notice_character=8'h4f;
  10:notice_character=8'h52;
  11:notice_character=8'h20;
  12:notice_character=8'h20;
  13:notice_character=8'h20;
  14:notice_character=8'h20;
  default:notice_character=0;
 endcase
 default:notice_character=0;
 endcase
end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin notice_code<=0;notice_visible<=0;end
 else begin notice_code<=notice;notice_visible<=notice!=0;end
end
always @*begin
 ch=notice_character(notice_code,dx[7:4]);
 case(ch)
  "P":glyph=35'b11110_10001_10001_11110_10000_10000_10000;
  "H":glyph=35'b10001_10001_10001_11111_10001_10001_10001;
  "A":glyph=35'b01110_10001_10001_11111_10001_10001_10001;
  "W":glyph=35'b10001_10001_10001_10101_10101_11011_10001;
  "R":glyph=35'b11110_10001_10001_11110_10100_10010_10001;
  "D":glyph=35'b11110_10001_10001_10001_10001_10001_11110;
  "L":glyph=35'b10000_10000_10000_10000_10000_10000_11111;
  "O":glyph=35'b01110_10001_10001_10001_10001_10001_01110;
  "I":glyph=35'b11111_00100_00100_00100_00100_00100_11111;
  "N":glyph=35'b10001_11001_11001_10101_10011_10011_10001;
  "G":glyph=35'b01110_10001_10000_10111_10001_10001_01110;
  "T":glyph=35'b11111_00100_00100_00100_00100_00100_00100;
  "F":glyph=35'b11111_10000_10000_11110_10000_10000_10000;
  "U":glyph=35'b10001_10001_10001_10001_10001_10001_01110;
  "E":glyph=35'b11111_10000_10000_11110_10000_10000_11111;
  default:glyph=0;
 endcase
 ink=letters && dx[3:1]<5 && glyph[34-(dy[3:1]*5+dx[3:1])];
end
assign rgb_out=box ? (ink ? 24'hffffff:24'h202020):rgb_in;
endmodule
