// Input follows frame_pixels (two clocks from the raster). The original
// award effect takes five clocks; nineteen more align with HDMI's 26 clocks.
module photo_award_render #(parameter RELIEF_ENABLE=0,SHARED_ENABLE=1,REMOTE_RELIEF=0,SHARED_MATH=0,EARLY_COLUMN=0)(
 input relief_mode,touch_contact,input [10:0] cursor_x,input [9:0] cursor_y,
 input mem_clk,mem_rst,input [20:0] light_base,
 output light_wide,output light_request,output [20:0] light_address,input light_ack,input [31:0] light_data,input light_valid,
 input de_in,input clk,rst,enable,pause,frame_tick,
 input [10:0] x,early_x,input [9:0] y,input [23:0] tagged_rgb,
 output [23:0] rgb,output [23:0] menu_rgb,
 output [3:0] light_error,output [6:0] light_frame,
 output [31:0] relief_descriptor,input relief_sent,input [31:0] relief_sent_descriptor,
 output relief_available,input relief_begin,relief_word_valid,relief_finish,relief_commit,
 input [8:0] relief_word_index,input [31:0] relief_word,
 output wall_we,output [7:0] wall_wa,wall_ra,output [23:0] wall_wd,input [23:0] wall_rgb
);
wire relief=RELIEF_ENABLE && relief_mode;
wire signed [8:0] blend_delta_r,blend_delta_g;
wire [3:0] blend_alpha;wire blend_request;
wire signed [5:0] normal_x,normal_y,normal_lx,normal_ly;
wire signed [14:0] shared_product_x,shared_product_y;
generate if(SHARED_MATH)begin:shared_pixel_math
 photo_award_math_bank bank(.clk(clk),.rst(rst),.blend_request(blend_request),
  .blend_r(blend_delta_r),.blend_g(blend_delta_g),.alpha(blend_alpha),
  .normal_x(normal_x),.normal_y(normal_y),.light_x(normal_lx),.light_y(normal_ly),
  .product_x(shared_product_x),.product_y(shared_product_y));
end else begin
 assign shared_product_x=0;assign shared_product_y=0;
end endgenerate
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
wire remote_valid,remote_bank,remote_palette_we;wire [8:0] remote_palette_wa;wire [31:0] remote_palette_wd;
wire [4:0] desired_angle,remote_angle;wire signed [5:0] desired_light_x,desired_light_y,remote_light_x,remote_light_y;
wire [6:0] wall_address;
assign wall_ra={remote_bank,wall_address};
generate if(REMOTE_RELIEF)begin:remote_tables
 photo_relief_tables_compact_a control(.clk(clk),.rst(rst),.enable(enable && relief),.frame_tick(frame_tick),
  .desired_angle(desired_angle),.desired_light_x(desired_light_x),.desired_light_y(desired_light_y),
  .request_descriptor(relief_descriptor),.request_sent(relief_sent),.sent_descriptor(relief_sent_descriptor),
  .available(relief_available),.begin_packet(relief_begin),.word_valid(relief_word_valid),.finish_packet(relief_finish),.commit_packet(relief_commit),
  .word_index(relief_word_index),.word_data(relief_word),.active_valid(remote_valid),.active_bank(remote_bank),
  .display_angle(remote_angle),.display_light_x(remote_light_x),.display_light_y(remote_light_y),
  .wall_we(wall_we),.wall_wa(wall_wa),.wall_wd(wall_wd),
  .mem_clk(mem_clk),.mem_rst(mem_rst),.mem_enable(relief_mem),
  .palette_we(remote_palette_we),.palette_wa(remote_palette_wa),.palette_wd(remote_palette_wd),.rejected());
end else begin
 assign relief_descriptor=0;assign relief_available=0;assign wall_we=0;assign wall_wa=0;assign wall_wd=0;
 assign remote_valid=0;assign remote_bank=0;assign remote_angle=0;assign remote_light_x=0;assign remote_light_y=0;
 assign remote_palette_we=0;assign remote_palette_wa=0;assign remote_palette_wd=0;
end endgenerate
// A newly entered trophy cannot publish its first table before the old
// foil pipeline drains. Nonzero foil opacity always owns the shared pair;
// zero opacity is exactly background and needs no multiplier.
`ifdef SHARED_DSP_CHECK
always @(posedge clk)if(!rst && SHARED_MATH && enable && relief && remote_valid && blend_request)
 $fatal(1,"shared DSP ownership overlaps visible trophy and foil work");
`endif
wire old_cache_we,new_cache_we;wire [8:0] old_cache_wa,old_cache_ra;
wire [7:0] new_cache_wa,new_cache_ra;wire [31:0] old_cache_wd,new_cache_wd,shared_cache_data;
generate if(RELIEF_ENABLE && SHARED_ENABLE)begin:shared_award_cache
 photo_relief_ram #(.ADDRESS_BITS(9),.DEPTH(512)) memory(
 .wc(mem_clk),.we(relief_mem ? (REMOTE_RELIEF ? remote_palette_we:new_cache_we):old_cache_we),
 .wa(relief_mem ? (REMOTE_RELIEF ? remote_palette_wa:{1'b0,new_cache_wa}):old_cache_wa),.wd(relief_mem ? (REMOTE_RELIEF ? remote_palette_wd:new_cache_wd):old_cache_wd),
 .rc(clk),.ra(relief ? {REMOTE_RELIEF && remote_bank,new_cache_ra}:old_cache_ra),.rd(shared_cache_data));
end else begin
 assign shared_cache_data=0;
end endgenerate
generate if(RELIEF_ENABLE)begin:gold
 photo_relief_player #(.SHARED_MATH(SHARED_MATH),.REMOTE_RELIEF(REMOTE_RELIEF),.SHARED_PALETTE(SHARED_ENABLE)) player(
 .math_nx(normal_x),.math_ny(normal_y),.math_lx(normal_lx),.math_ly(normal_ly),
 .math_product_x(shared_product_x),.math_product_y(shared_product_y),.remote_valid(remote_valid),.remote_angle(remote_angle),.remote_light_x(remote_light_x),.remote_light_y(remote_light_y),
 .desired_angle(desired_angle),.desired_light_x(desired_light_x),.desired_light_y(desired_light_y),.wall_address(wall_address),.wall_rgb(wall_rgb),.mem_clk(mem_clk),.mem_rst(mem_rst),.enable(enable && relief),.base(light_base),
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
award_fx #(.SHARED_MATH(SHARED_MATH),.EARLY_COLUMN(EARLY_COLUMN),.INITIAL_HOLD_FRAMES(0)) effect(
 .math_delta_r(blend_delta_r),.math_delta_g(blend_delta_g),.math_alpha(blend_alpha),.math_request(blend_request),
 .math_product_r(shared_product_x),.math_product_g(shared_product_y),.clk(clk),.rst(rst),.enable(enable && !relief),.pause(pause),.frame_tick(frame_tick),
 .x(x),.early_x(early_x),.y(y),.base_rgb(base),.tag(pixel[5:0]),.rgb(effect_rgb));
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
generate if(REMOTE_RELIEF)begin:compact_delay
 photo_award_delay_lut video_delay(.clk(clk),.rst(rst),.rgb_in(relief ? new_rgb:light_rgb),.rgb(rgb),.menu_rgb(menu_rgb));
end else begin:legacy_delay
 photo_award_delay video_delay(.clk(clk),.rst(rst),.rgb_in(relief ? new_rgb:light_rgb),.rgb(rgb),.menu_rgb(menu_rgb));
end endgenerate
endmodule

// Coordinates and RGB arrive together at the existing 21-cycle menu tap.
// The small combinational banner adds no video latency or font RAM.
module photo_award_notice(input clk,rst,input [2:0] notice,input [11:0] x,input [10:0] y,
 input [23:0] rgb_in,output [23:0] rgb_out);
reg notice_visible;reg [2:0] notice_code;
wire box=notice_visible && x>=16 && x<280 && y>=16 && y<48;
wire letters=x>=24 && x<264 && y>=22 && y<36;
// Subtracting 24 modulo one 16-pixel cell only flips this column bit.
wire [2:0] column={~x[3],x[2:1]};
// Select compact glyph IDs directly from raw half-cell positions. This
// removes the X subtraction before the character mux, the 35-bit glyph
// mux and the row*5+column barrel index. No state or pixel latency is added.
function [3:0] notice_glyph;input [2:0] code;input [5:0] half_cell;begin
 notice_glyph=0;case(code)
 1:case(half_cell)
  6'd3,6'd4,6'd7,6'd8,6'd19,6'd20:notice_glyph=4'd3;
  6'd5,6'd6:notice_glyph=4'd4;
  6'd9,6'd10:notice_glyph=4'd5;
  6'd11,6'd12,6'd21,6'd22:notice_glyph=4'd6;
  6'd15,6'd16:notice_glyph=4'd7;
  6'd17,6'd18:notice_glyph=4'd8;
  6'd23,6'd24:notice_glyph=4'd9;
  6'd25,6'd26:notice_glyph=4'd10;
  6'd27,6'd28:notice_glyph=4'd11;
  default:notice_glyph=0;
 endcase
 2:case(half_cell)
  6'd3,6'd4,6'd7,6'd8:notice_glyph=4'd3;
  6'd5,6'd6:notice_glyph=4'd4;
  6'd9,6'd10:notice_glyph=4'd5;
  6'd11,6'd12,6'd31,6'd32:notice_glyph=4'd6;
  6'd17,6'd18,6'd25,6'd26:notice_glyph=4'd8;
  6'd15,6'd16,6'd29,6'd30:notice_glyph=4'd10;
  6'd19,6'd20:notice_glyph=4'd12;
  6'd23,6'd24:notice_glyph=4'd13;
  6'd27,6'd28:notice_glyph=4'd14;
  default:notice_glyph=0;
 endcase
 3:case(half_cell)
  6'd3,6'd4,6'd7,6'd8:notice_glyph=4'd3;
  6'd5,6'd6:notice_glyph=4'd4;
  6'd9,6'd10,6'd17,6'd18,6'd19,6'd20,6'd23,6'd24:notice_glyph=4'd5;
  6'd11,6'd12:notice_glyph=4'd6;
  6'd21,6'd22:notice_glyph=4'd8;
  6'd15,6'd16:notice_glyph=4'd15;
  default:notice_glyph=0;
 endcase
 4:case(half_cell)
  6'd3,6'd4:notice_glyph=4'd1;
  6'd5,6'd6:notice_glyph=4'd2;
  6'd17,6'd18,6'd19,6'd20,6'd23,6'd24:notice_glyph=4'd5;
  6'd7,6'd8,6'd11,6'd12,6'd21,6'd22:notice_glyph=4'd8;
  6'd9,6'd10:notice_glyph=4'd12;
  6'd15,6'd16:notice_glyph=4'd15;
  default:notice_glyph=0;
 endcase
 default:notice_glyph=0;endcase
end endfunction
wire [3:0] glyph_id=notice_glyph(notice_code,x[8:3]);
reg [4:0] row_bits;
// Y starts at 22: its raw row codes are 3,4,5,6,7,0,1.
always @*case({glyph_id,y[3:1]})
 7'd72,7'd76,7'd77,7'd78,7'd79,7'd96,7'd97,7'd100,7'd101,7'd102,7'd103:row_bits=5'b00100;
 7'd27,7'd65,7'd67,7'd89,7'd91,7'd113:row_bits=5'b01110;
 7'd8,7'd9,7'd15,7'd56,7'd59,7'd60,7'd61,7'd62,7'd63,7'd93,7'd104,7'd105,7'd108,7'd109,7'd111,7'd120,7'd124,7'd125,7'd127:row_bits=5'b10000;
 7'd12,7'd13,7'd16,7'd17,7'd19,7'd20,7'd21,7'd23,7'd24,7'd25,7'd28,7'd29,7'd31,7'd33,7'd35,7'd36,7'd37,7'd41,7'd44,7'd45,7'd48,7'd52,7'd53,7'd54,7'd55,7'd64,7'd68,7'd69,7'd70,7'd71,7'd81,7'd83,7'd88,7'd92,7'd95,7'd112,7'd115,7'd116,7'd117,7'd118,7'd119:row_bits=5'b10001;
 7'd40:row_bits=5'b10010;
 7'd80,7'd87:row_bits=5'b10011;
 7'd47:row_bits=5'b10100;
 7'd38,7'd39,7'd86:row_bits=5'b10101;
 7'd94:row_bits=5'b10111;
 7'd84,7'd85:row_bits=5'b11001;
 7'd32:row_bits=5'b11011;
 7'd11,7'd14,7'd43,7'd46,7'd49,7'd51,7'd110,7'd126:row_bits=5'b11110;
 7'd22,7'd30,7'd57,7'd73,7'd75,7'd99,7'd107,7'd121,7'd123:row_bits=5'b11111;
 default:row_bits=0;endcase
wire ink=letters && column<5 && row_bits[4-column];
always @(posedge clk or posedge rst)begin
 if(rst)begin notice_code<=0;notice_visible<=0;end
 else begin notice_code<=notice;notice_visible<=notice!=0;end
end
assign rgb_out=box ? (ink ? 24'hffffff:24'h202020):rgb_in;
endmodule
