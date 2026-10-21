`timescale 1ns/1ps
// One frame-locked menu for image, audio and playback controls.
module photo_settings_overlay #(parameter VIDEO_DELAY=21,INTERVAL_CONTROL=0)(
 input clk,rst,frame_tick,de,settings_mode,updating,
 input [11:0] x,input [10:0] y,input [3:0] setting_item,
 input [3:0] volume,brightness,contrast,saturation,input [1:0] sharpness,enhancement,
 input invert,vintage,input [4:0] effect,input edge_enable,auto_enable,waveform_mode,high_color,audio_repair_enable,
 input [23:0] rgb_in,output [23:0] rgb_out,input [4:0] auto_interval_seconds
);
reg visible,pending;reg [3:0] selected;
reg [4:0] values[0:14];
always @(posedge clk or posedge rst)begin
 if(rst)begin visible<=0;pending<=0;selected<=0;
  values[14]<=5;values[0]<=5;values[1]<=4;values[2]<=4;values[3]<=1;values[4]<=4;
  values[5]<=0;values[6]<=0;values[7]<=1;values[8]<=0;values[9]<=0;values[10]<=0;values[11]<=0;values[12]<=0;values[13]<=0;
 end else if(frame_tick)begin
  values[14]<=auto_interval_seconds;visible<=settings_mode;pending<=updating;selected<=setting_item;
  values[0]<=volume;values[1]<=brightness;values[2]<=contrast;values[3]<={2'd0,sharpness};values[4]<=saturation;
  values[5]<={3'd0,invert};values[6]<={3'd0,vintage};values[7]<={2'd0,enhancement};
  values[8]<=effect;values[9]<={3'd0,auto_enable};values[10]<={3'd0,waveform_mode};values[11]<={3'd0,high_color};values[12]<={4'd0,audio_repair_enable};values[13]<={4'd0,edge_enable};
 end
end
function [6:0] text_glyph;
 input [5:0] text_id;input [4:0] index;
 begin text_glyph=0;case(text_id)
   0:case(index)
    0:text_glyph=7'd48;
    1:text_glyph=7'd49;
    2:text_glyph=7'd50;
    3:text_glyph=7'd51;
    default:text_glyph=0;
   endcase
   1:case(index)
    0:text_glyph=7'd5;
    1:text_glyph=7'd6;
    default:text_glyph=0;
   endcase
   2:case(index)
    0:text_glyph=7'd7;
    1:text_glyph=7'd8;
    default:text_glyph=0;
   endcase
   3:case(index)
    0:text_glyph=7'd9;
    1:text_glyph=7'd10;
    default:text_glyph=0;
   endcase
   4:case(index)
    0:text_glyph=7'd11;
    1:text_glyph=7'd12;
    default:text_glyph=0;
   endcase
   5:case(index)
    0:text_glyph=7'd13;
    1:text_glyph=7'd14;
    default:text_glyph=0;
   endcase
   6:case(index)
    0:text_glyph=7'd15;
    1:text_glyph=7'd16;
    default:text_glyph=0;
   endcase
   7:case(index)
    0:text_glyph=7'd17;
    1:text_glyph=7'd18;
    default:text_glyph=0;
   endcase
   8:case(index)
    0:text_glyph=7'd52;
    1:text_glyph=7'd53;
    2:text_glyph=7'd54;
    3:text_glyph=7'd55;
    default:text_glyph=0;
   endcase
   9:case(index)
    0:text_glyph=7'd56;
    1:text_glyph=7'd57;
    2:text_glyph=7'd58;
    3:text_glyph=7'd59;
    default:text_glyph=0;
   endcase
   10:case(index)
    0:text_glyph=7'd23;
    1:text_glyph=7'd24;
    2:text_glyph=7'd25;
    default:text_glyph=0;
   endcase
   11:case(index)
    0:text_glyph=7'd26;
    1:text_glyph=7'd27;
    2:text_glyph=7'd28;
    default:text_glyph=0;
   endcase
   12:case(index)
    0:text_glyph=7'd45;
    1:text_glyph=7'd46;
    2:text_glyph=7'd47;
    3:text_glyph=7'd36;
    4:text_glyph=7'd29;
    5:text_glyph=7'd30;
    6:text_glyph=7'd0;
    7:text_glyph=7'd0;
    8:text_glyph=7'd45;
    9:text_glyph=7'd46;
    10:text_glyph=7'd47;
    11:text_glyph=7'd37;
    12:text_glyph=7'd31;
    default:text_glyph=0;
   endcase
   13:case(index)
    0:text_glyph=7'd45;
    1:text_glyph=7'd46;
    2:text_glyph=7'd47;
    3:text_glyph=7'd38;
    4:text_glyph=7'd32;
    5:text_glyph=7'd33;
    6:text_glyph=7'd0;
    7:text_glyph=7'd0;
    8:text_glyph=7'd45;
    9:text_glyph=7'd46;
    10:text_glyph=7'd47;
    11:text_glyph=7'd39;
    12:text_glyph=7'd34;
    default:text_glyph=0;
   endcase
   14:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd61;
    default:text_glyph=0;
   endcase
   15:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd62;
    2:text_glyph=7'd63;
    3:text_glyph=7'd64;
    default:text_glyph=0;
   endcase
   16:case(index)
    0:text_glyph=7'd62;
    1:text_glyph=7'd65;
    default:text_glyph=0;
   endcase
   17:case(index)
    0:text_glyph=7'd66;
    1:text_glyph=7'd67;
    default:text_glyph=0;
   endcase
   18:case(index)
    0:text_glyph=7'd68;
    1:text_glyph=7'd69;
    default:text_glyph=0;
   endcase
   19:case(index)
    0:text_glyph=7'd70;
    1:text_glyph=7'd71;
    default:text_glyph=0;
   endcase
   20:case(index)
    0:text_glyph=7'd72;
    1:text_glyph=7'd73;
    default:text_glyph=0;
   endcase
   21:case(index)
    0:text_glyph=7'd74;
    1:text_glyph=7'd75;
    2:text_glyph=7'd76;
    3:text_glyph=7'd77;
    default:text_glyph=0;
   endcase
   22:case(index)
    0:text_glyph=7'd78;
    1:text_glyph=7'd79;
    2:text_glyph=7'd78;
    3:text_glyph=7'd80;
    default:text_glyph=0;
   endcase
   23:case(index)
    0:text_glyph=7'd81;
    1:text_glyph=7'd82;
    2:text_glyph=7'd83;
    3:text_glyph=7'd84;
    default:text_glyph=0;
   endcase
   24:case(index)
    0:text_glyph=7'd85;
    1:text_glyph=7'd86;
    2:text_glyph=7'd87;
    3:text_glyph=7'd88;
    default:text_glyph=0;
   endcase
   25:case(index)
    0:text_glyph=7'd89;
    1:text_glyph=7'd90;
    2:text_glyph=7'd83;
    3:text_glyph=7'd84;
    default:text_glyph=0;
   endcase
   26:case(index)
    0:text_glyph=7'd91;
    1:text_glyph=7'd92;
    2:text_glyph=7'd93;
    default:text_glyph=0;
   endcase
   27:case(index)
    0:text_glyph=7'd94;
    1:text_glyph=7'd95;
    2:text_glyph=7'd96;
    3:text_glyph=7'd97;
    default:text_glyph=0;
   endcase
   28:case(index)
    0:text_glyph=7'd98;
    1:text_glyph=7'd99;
    default:text_glyph=0;
   endcase
   29:case(index)
    0:text_glyph=7'd100;
    1:text_glyph=7'd96;
    2:text_glyph=7'd97;
    default:text_glyph=0;
   endcase
   30:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd62;
    2:text_glyph=7'd101;
    3:text_glyph=7'd102;
    default:text_glyph=0;
   endcase
   31:case(index)
    0:text_glyph=7'd103;
    1:text_glyph=7'd104;
    2:text_glyph=7'd105;
    3:text_glyph=7'd106;
    default:text_glyph=0;
   endcase
   32:case(index)
    0:text_glyph=7'd107;
    1:text_glyph=7'd61;
    2:text_glyph=7'd108;
    3:text_glyph=7'd109;
    default:text_glyph=0;
   endcase
   33:case(index)
    0:text_glyph=7'd110;
    1:text_glyph=7'd111;
    2:text_glyph=7'd112;
    3:text_glyph=7'd113;
    default:text_glyph=0;
   endcase
   34:case(index)
    0:text_glyph=7'd114;
    1:text_glyph=7'd115;
    2:text_glyph=7'd116;
    3:text_glyph=7'd117;
    default:text_glyph=0;
   endcase
   35:case(index)
    0:text_glyph=7'd60;
    1:text_glyph=7'd118;
    2:text_glyph=7'd119;
    3:text_glyph=7'd120;
    default:text_glyph=0;
   endcase
   36:case(index)
    0:text_glyph=7'd121;
    1:text_glyph=7'd86;
    2:text_glyph=7'd122;
    3:text_glyph=7'd123;
    default:text_glyph=0;
   endcase
   37:case(index)
    0:text_glyph=7'd58;1:text_glyph=7'd59;2:text_glyph=7'd124;3:text_glyph=7'd125;default:text_glyph=0;
   endcase
   default:text_glyph=0;
 endcase end
endfunction

wire panel=de && visible && x>=64 && x<864 && y>=80 && y<688;
wire [10:0] row_y=y-11'd144;
wire [3:0] row_index=row_y[8:5];
wire [4:0] row_local=row_y[4:0];
wire [11:0] label_x=x-12'd96,value_x=x-12'd608;
wire [10:0] label_y=y-11'd96,footer_y=y-(INTERVAL_CONTROL ? 11'd640:11'd608);
reg [6:0] glyph;reg [3:0] font_row,font_col;
reg use_table;reg [5:0] glyph_id;reg [4:0] glyph_index;
reg text_on,highlight,bar,track;reg [4:0] value;reg [8:0] bar_width;
reg [5:0] value_label;
reg [1:0] text_color;
always @*begin
 glyph=0;use_table=0;glyph_id=0;glyph_index=0;font_row=0;font_col=0;text_on=0;highlight=0;bar=0;track=0;
 value=0;bar_width=0;value_label=0;text_color=2'd0;
 if(panel)begin
  if(y>=96 && y<128 && x>=96 && x<224)begin
   use_table=1;glyph_id=0;glyph_index=label_x[8:5];font_row=label_y[4:1];font_col=label_x[4:1];text_on=1;text_color=2'd1;
  end else if(y>=96 && y<128 && x>=688 && x<784)begin
   use_table=1;glyph_id=pending ? 10:11;glyph_index=(x-688)>>5;font_row=label_y[4:1];font_col=(x-688)>>1;text_on=1;
   text_color=pending ? 2'd2:2'd1;
  end else if(y>=144 && y<(INTERVAL_CONTROL ? 624:592) && row_index<=(INTERVAL_CONTROL ? 14:13))begin
   value=values[row_index];highlight=row_index==selected;
   case(row_index)
    // Signed-digit constants; nine-bit arithmetic preserves the old wrap.
    0,1,2,4:bar_width=({4'd0,value}<<5)-({4'd0,value}<<2);
    3:bar_width=({4'd0,value}<<6)+({4'd0,value}<<3);
    7:bar_width=({4'd0,value}<<7)-({4'd0,value}<<4);
    default:bar_width=0;
   endcase
   case(row_index)
    5,6,9,12,13:value_label=value==0 ? 18:19;
    8:value_label=value==11 ? 6'd36:value>=7 ? 6'd24+value:6'd20+value;
    10:value_label=value==0 ? 16:17;
    11:value_label=value==0 ? 28:29;
    default:value_label=0;
   endcase
   if(x>=96 && x<288)begin
    use_table=1;glyph_id=row_index==14 ? 6'd37:row_index==13 ? 6'd35:row_index==12 ? 6'd30:row_index==0 ? 5'd14:row_index==10 ? 5'd15:row_index==11 ? 5'd27:{1'b0,row_index};glyph_index=label_x[8:5];
    font_col=label_x[4:1];font_row=row_local[4:1];text_on=1;
   end else if(x>=608 && x<800)begin
    if(value_label!=0)begin use_table=1;glyph_id=value_label;glyph_index=value_x[8:5];end
    else if(INTERVAL_CONTROL && row_index==14)begin
     case(value_x[8:5])
      0:glyph=7'd35+(value>=30 ? 3:value>=20 ? 2:value>=10 ? 1:0);
      1:glyph=7'd35+(value>=30 ? value-30:value>=20 ? value-20:value>=10 ? value-10:value);
      2:glyph=7'd126;default:glyph=0;
     endcase
    end else glyph=value_x[8:5]==0 ? 7'd35+value:7'd0;
    font_col=value_x[4:1];font_row=row_local[4:1];text_on=1;text_color=2'd2;
   end
   if(value_label==0 && row_index!=14 && row_local>=10 && row_local<22 && x>=320 && x<544)begin track=1;bar=x-320<bar_width;end
  end else if(y>=(INTERVAL_CONTROL ? 640:608) && y<(INTERVAL_CONTROL ? 680:648) && x>=96 && x<400)begin
   if((y<(INTERVAL_CONTROL ? 656:624)) || (y>=(INTERVAL_CONTROL ? 664:632)))begin
    use_table=1;glyph_id=y<(INTERVAL_CONTROL ? 656:624) ? 12:13;glyph_index=label_x[8:4];font_col=label_x[3:0];
    font_row=y<(INTERVAL_CONTROL ? 656:624) ? footer_y[3:0]:(y-(INTERVAL_CONTROL ? 664:632));text_on=1;text_color=2'd1;
   end
  end
 end
end
// Separate raster/row decoding from the glyph table, retaining total latency.
// The legacy four-cycle configuration has no spare stage and stays direct.
localparam EXTRA_STAGE=VIDEO_DELAY>=5 ? 1:0;
reg table_q;reg [5:0] id_q;reg [4:0] index_q;reg [6:0] numeric_q;
reg [3:0] row_q,col_q;reg panel_q,text_q;reg [1:0] color_q,bg_q;
wire [6:0] direct_glyph=use_table ? text_glyph(glyph_id,glyph_index):glyph;
wire [6:0] staged_glyph=table_q ? text_glyph(id_q,index_q):numeric_q;
reg [6:0] glyph_s1;reg [3:0] row_s1,col_s1,col_s2;
reg panel_s1,panel_s2,text_s1,text_s2,ink_s3;
reg [1:0] bg_s3,color_s3;
reg [1:0] bg_s1,bg_s2,color_s1,color_s2;
wire [15:0] font_bits;
wire [6:0] lookup_glyph;
generate if(EXTRA_STAGE)begin: text_rom_stage
 wire [7:0] lookup_word;reg table_s1,overflow_s1;reg [6:0] numeric_s1;
 photo_menu_text_lookup text_lookup(.clk(clk),.address({id_q,index_q[3:0]}),.data(lookup_word));
 always @(posedge clk or posedge rst)
  if(rst)begin table_s1<=0;overflow_s1<=0;numeric_s1<=0;end
  else begin table_s1<=table_q;overflow_s1<=index_q[4];numeric_s1<=numeric_q;end
 assign lookup_glyph=table_s1 ? (overflow_s1 ? 7'd0:lookup_word[6:0]):numeric_s1;
end else begin: direct_text
 assign lookup_glyph=glyph_s1;
end endgenerate
photo_menu_font font(.clk(clk),.glyph(lookup_glyph),.row(row_s1),.bits(font_bits));
reg [VIDEO_DELAY-3-EXTRA_STAGE:0] panel_pipe;
// Delay palette indices instead of duplicating constant RGB bits at every tap.
reg [2:0] color_pipe[0:VIDEO_DELAY-4-EXTRA_STAGE];integer i;
function [23:0] palette_rgb;input [2:0] index;begin
 case(index)
  0:palette_rgb=24'h142332;
  1:palette_rgb=24'h20405a;
  2:palette_rgb=24'h334456;
  3:palette_rgb=24'h32b8d4;
  4:palette_rgb=24'hebebeb;
  5:palette_rgb=24'h7de3ff;
  6:palette_rgb=24'hffd166;
  default:palette_rgb=24'd0;
 endcase
end endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin
  table_q<=0;id_q<=0;index_q<=0;numeric_q<=0;row_q<=0;col_q<=0;panel_q<=0;text_q<=0;color_q<=0;bg_q<=0;
  glyph_s1<=0;row_s1<=0;col_s1<=0;col_s2<=0;panel_s1<=0;panel_s2<=0;text_s1<=0;text_s2<=0;
  bg_s1<=0;bg_s2<=0;color_s1<=0;color_s2<=0;bg_s3<=0;color_s3<=0;ink_s3<=0;panel_pipe<=0;
  for(i=0;i<VIDEO_DELAY-3-EXTRA_STAGE;i=i+1)color_pipe[i]<=0;
 end else begin
  table_q<=use_table;id_q<=glyph_id;index_q<=glyph_index;numeric_q<=glyph;
  row_q<=font_row;col_q<=font_col;panel_q<=panel;text_q<=text_on;color_q<=text_color;
  bg_q<=bar ? 2'd3:track ? 2'd2:highlight ? 2'd1:2'd0;
  glyph_s1<=EXTRA_STAGE ? staged_glyph:direct_glyph;
  row_s1<=EXTRA_STAGE ? row_q:font_row;col_s1<=EXTRA_STAGE ? col_q:font_col;
  panel_s1<=EXTRA_STAGE ? panel_q:panel;text_s1<=EXTRA_STAGE ? text_q:text_on;color_s1<=EXTRA_STAGE ? color_q:text_color;
  bg_s1<=EXTRA_STAGE ? bg_q:(bar ? 2'd3:track ? 2'd2:highlight ? 2'd1:2'd0);
  panel_s2<=panel_s1;text_s2<=text_s1;col_s2<=col_s1;color_s2<=color_s1;bg_s2<=bg_s1;
  panel_pipe<={panel_pipe[VIDEO_DELAY-4-EXTRA_STAGE:0],panel_s2};
  // Split BRAM bit selection and colour fanout; remove one later delay
  // stage to preserve the established VIDEO_DELAY at the output.
  ink_s3<=text_s2 && font_bits[15-col_s2];bg_s3<=bg_s2;color_s3<=color_s2;
  color_pipe[0]<=ink_s3 ? {1'b1,color_s3}:{1'b0,bg_s3};
  for(i=1;i<VIDEO_DELAY-3-EXTRA_STAGE;i=i+1)color_pipe[i]<=color_pipe[i-1];
 end
end
assign rgb_out=panel_pipe[VIDEO_DELAY-3-EXTRA_STAGE] ? palette_rgb(color_pipe[VIDEO_DELAY-4-EXTRA_STAGE]):rgb_in;
endmodule

// Compact text-id/character-position map. Bitmap fonts stay in their original ROMs.
module photo_menu_text_lookup(input clk,input [9:0] address,output [7:0] data);
`ifdef TOUCHSCREEN_SIM
reg [7:0] rom[0:1023];reg [7:0] q;
initial $readmemh("src/board_a/user_source/hdl_source/photo_menu_text_lookup.hex",rom);
always @(posedge clk)q<=rom[address];
assign data=q;
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.ADDR_WIDTH_A(10),.DATA_DEPTH_A(1024),
 .DATA_WIDTH_B(8),.ADDR_WIDTH_B(10),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.MODE("SP"),
 .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.DEBUGGABLE("NO"),.PACKABLE("NO"),
 .FORCE_KEEP("OFF"),.INIT_FILE("../src/board_a/user_source/hdl_source/photo_menu_text_lookup.mif"),.FILL_ALL("NONE"),.IMPLEMENT("9K")) map_rom(
 .doa(data),.dob(),.dia(8'd0),.dib(8'd0),.cea(1'b1),.ocea(1'b0),.clka(clk),.wea(1'b0),.rsta(1'b0),
 .ceb(1'b0),.oceb(1'b0),.clkb(1'b0),.web(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(address),.addrb(10'd0));
`endif
endmodule
