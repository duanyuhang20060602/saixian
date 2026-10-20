`timescale 1ns/1ps
// Raw SDRAM remains reusable when controls change. Process each transmitted
// frame with one immutable settings snapshot, then pack back to RGB565.
module photo_b_processing #(parameter FRAME_WORDS=460800)(
 input clk,rst,start,abort,read_req,effect_plane,source_ack,source_empty,
 input [31:0] source_data,input [18:0] settings_state,input [1:0] image_gain,
 output source_read,input read_en,output empty,output [31:0] data
);
localparam WAIT_ACK=0,WAIT_LOW=1,SETTLE=2,FETCH=3,HIGH=4,LOW=5,FINISH=6,COLOR0=7,COLOR1=8,COLOR2=9,COLOR3=10;
reg [3:0] state;reg [2:0] settle;
reg ack_meta,ack_sync,running;
reg [18:0] frame_settings;reg [1:0] frame_gain;
reg [19:0] issued;reg [5:0] credits,queued;
reg [4:0] wp,rp;
reg [15:0] low_pixel,first_pixel;reg half;
reg [10:0] x;reg [9:0] y;
wire high_color=frame_settings[18];
reg [1:0] color_phase;reg [15:0] color_tail;reg [23:0] color_last;
wire [20:0] frame_words=high_color ? 21'd691200:FRAME_WORDS;
wire input_valid=running && (state==HIGH || state==LOW || state==COLOR0 || state==COLOR1 || state==COLOR2 || state==COLOR3);
wire [15:0] pixel=state==HIGH ? source_data[31:16]:low_pixel;
wire [23:0] rgb565_expanded={pixel[15:11],pixel[15:13],pixel[10:5],pixel[10:9],pixel[4:0],pixel[4:2]};
wire [23:0] rgb=high_color ?
 (state==COLOR0 ? source_data[31:8]:state==COLOR1 ? {color_tail[7:0],source_data[31:16]}:
  state==COLOR2 ? {color_tail,source_data[31:24]}:color_last):rgb565_expanded;
assign source_read=running && state==FETCH && !source_empty && credits<32 && issued<frame_words;
assign empty=queued==0;
wire pop=read_en && !empty;
wire [23:0] enhanced,adjusted,styled;
wire enhanced_de;wire [10:0] enhanced_x;
wire pipeline_reset=rst || !running;
saixian_adaptive_enhance #(.WIDTH(1280),.SPLIT_X(640),.PHOTO_SMOOTH(1),.EXTERNAL_GAIN(1)) enhance(
 .clk(clk),.rst(pipeline_reset),.de(input_valid),.vs(1'b0),.frame_tick(1'b0),.statistics_enable(1'b0),
 .x(x),.y(y),.rgb_in(rgb),.mode(frame_settings[3:2]),.strength(frame_settings[5:4]),.external_gain(frame_gain),
 .rgb_out(enhanced),.de_out(enhanced_de),.vs_out(),.x_out(enhanced_x),.y_out(),.gain_out());
saixian_picture_adjust_pipe adjust(.clk(clk),.rst(pipeline_reset),.de(enhanced_de),.x(enhanced_x),.rgb_in(enhanced),
 .brightness_setting(frame_settings[17:14]),.contrast_setting(frame_settings[13:10]),
 .saturation_setting(frame_settings[9:6]),.sharpness_setting(2'd0),.rgb_out(adjusted));
saixian_hmi_color_style style(.rgb_in(adjusted),.invert(frame_settings[1]),.vintage(frame_settings[0]),.rgb_out(styled));
reg [7:0] adjusted_valid;
wire [15:0] processed={styled[23:19],styled[15:10],styled[7:3]};
wire native_push,aux_push,push;wire [31:0] native_output,aux_output,packed_output;
assign push=effect_plane ? aux_push:native_push;
assign packed_output=effect_plane ? aux_output:native_output;
water_pack auxiliary(.clk(clk),.rst(rst || start || abort),.write_req(1'b0),
 .pixel_valid(adjusted_valid[7] && !high_color),.pixel(styled),.full(1'b0),
 .valid(),.data(),.overflow(),.small_valid(aux_push),.small_data(aux_output));
photo_color_pack packing(.clk(clk),.rst(rst),.clear(start || abort),.high_color(high_color),
 .valid(adjusted_valid[7]),.rgb(styled),.word_valid(native_push),.word_data(native_output),.aligned());
// The queue's existing registered pop maps directly to the eRAM read port.
// Reset only publication validity, rather than clearing the pixel memory.
wire [31:0] queue_data;reg have_output;
photo_audio_word_ram #(.ADDR(5),.IMPLEMENT("9K")) output_queue(
 .clk(clk),.we(push && !rst && !start && !abort),.wa(wp),.wd(packed_output),
 .re(pop && !rst && !start && !abort),.ra(rp),.rd(queue_data));
always @(posedge clk or posedge rst)
 if(rst)have_output<=0;else if(start || abort)have_output<=0;else if(pop)have_output<=1;
assign data=have_output ? queue_data:32'd0;
// synthesis translate_off
always @(posedge clk)if(!rst && !start && !abort && push && pop && wp==rp)
 $fatal(1,"pixel queue has a cross-port eRAM address collision");
// synthesis translate_on
always @(posedge clk or posedge rst)begin
 if(rst)begin ack_meta<=0;ack_sync<=0;end
 else begin ack_meta<=source_ack;ack_sync<=ack_meta;end
end
always @(posedge clk or posedge rst)begin
 if(rst)begin
  state<=FINISH;settle<=0;running<=0;frame_settings<=0;frame_gain<=1;
  issued<=0;credits<=0;queued<=0;wp<=0;rp<=0;
  low_pixel<=0;first_pixel<=0;half<=0;color_phase<=0;color_tail<=0;color_last<=0;x<=0;y<=0;adjusted_valid<=0;
 end else if(start || abort)begin
  state<=start ? WAIT_ACK:FINISH;settle<=0;running<=0;
  frame_settings<=settings_state;frame_gain<=image_gain;
  issued<=0;credits<=0;queued<=0;wp<=0;rp<=0;
  half<=0;color_phase<=0;color_tail<=0;color_last<=0;x<=0;y<=0;adjusted_valid<=0;
 end else begin
  adjusted_valid<=running ? {adjusted_valid[6:0],enhanced_de}:8'd0;
  case(state)
   // The sender owns the ACK-high decision. Observe its request level,
   // so separate ACK synchronizers cannot miss the handshake by one clock.
   WAIT_ACK:if(read_req)state<=WAIT_LOW;
   WAIT_LOW:if(!ack_sync && !read_req)begin state<=SETTLE;settle<=0;end
   SETTLE:if(settle==4)begin state<=FETCH;running<=1;end else settle<=settle+1'b1;
   FETCH:if(source_read)begin issued<=issued+1'b1;state<=high_color ? (color_phase==0 ? COLOR0:color_phase==1 ? COLOR1:COLOR2):HIGH;end
         else if(issued==frame_words)state<=FINISH;
   HIGH:begin low_pixel<=source_data[15:0];state<=LOW;end
   LOW:state<=FETCH;
   COLOR0:begin color_tail<={8'd0,source_data[7:0]};color_phase<=1;state<=FETCH;end
   COLOR1:begin color_tail<=source_data[15:0];color_phase<=2;state<=FETCH;end
   COLOR2:begin color_last<=source_data[23:0];state<=COLOR3;end
   COLOR3:begin color_phase<=0;state<=FETCH;end
   default:;
  endcase
  if(input_valid)begin
   if(x==1279)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
  end
  case({source_read,pop})
   2'b10:credits<=credits+1'b1;
   2'b11:if(effect_plane)credits<=credits-1'b1;
   2'b01:credits<=credits-(effect_plane ? 2'd2:2'd1);
   default:;
  endcase
  if(push)wp<=wp+1'b1;
  if(pop)rp<=rp+1'b1;
  case({push,pop})
   2'b10:queued<=queued+1'b1;
   2'b01:queued<=queued-1'b1;
   default:;
  endcase
 end
end
endmodule
