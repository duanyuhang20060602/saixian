// Sample 112x63 cell centres from a completed RGB565 photo. One aligned
// 64-word turn supplies every centre that lies in that block, amortizing
// SDRAM response/recovery overhead without allocating another pixel buffer.
module photo_thumbnail_memory #(parameter BURST_WORDS=64)(
 input clk,rst,init_done,refresh,busy,frame_busy,allow_access,other_request,
 output request,claim,read_command,output [20:0] address,
 input response_valid,input [31:0] response,
 input video_clk,video_request,video_cancel,video_blank,input [1:0] video_slot,
 output reg video_done,input [12:0] video_address,output [15:0] video_data
);
localparam BW=$clog2(BURST_WORDS);
function [20:0] base;
 input [1:0] slot;
 begin case(slot)0:base=0;1:base=21'd1048576;default:base=21'd0;endcase end
endfunction
localparam IDLE=0,READ=1,RECOVER=2;
reg [1:0] state;
(* async_reg="true" *)reg [2:0] job_sync;
(* async_reg="true" *)reg [1:0] slot_meta,slot_sync;
(* async_reg="true" *)reg cancel_meta,cancel_sync,blank_meta,blank_sync;
reg job_seen,active,samples_done,block_done;
reg [6:0] column;reg [5:0] row;
reg [2:0] column_phase,row_phase;reg [12:0] cache_index;
reg [20:0] pixel_address;
reg [20-BW:0] block_address;
reg [BW:0] issued;reg [BW-1:0] received;reg [3:0] recovery;
wire [20:0] pixel_step=column==111 ?
 (row_phase>=4 ? 21'd7045:21'd6405):(column_phase>=2 ? 21'd6:21'd5);
assign request=active && blank_sync && !cancel_sync && allow_access && !other_request;
assign claim=state!=IDLE;
assign read_command=state==READ && issued<BURST_WORDS && !refresh;
assign address={block_address,issued[BW-1:0]};
// Samples advance monotonically inside a block. Latch its end once rather
// than compare the whole SDRAM address on every returned word.
wire [BW+2:0] next_sample_offset={3'b000,pixel_address[BW-1:0]}+
 (column_phase>=2 ? 7'd6:7'd5);
wire leave_block=column==111 || next_sample_offset>=BURST_WORDS;
wire write_sample=state==READ && response_valid && !samples_done && !block_done &&
 received==pixel_address[BW-1:0];
wire [15:0] sample=column_phase>=4 ? response[15:0]:response[31:16];
photo_thumbnail_cache cache(.write_clk(clk),.write_enable(write_sample),.write_address(cache_index),.write_data(sample),
 .read_clk(video_clk),.read_address(video_address),.read_data(video_data));
always @(posedge clk or posedge rst)
 if(rst)begin
  state<=IDLE;job_sync<=0;slot_meta<=0;slot_sync<=0;cancel_meta<=0;cancel_sync<=0;blank_meta<=0;blank_sync<=0;
  job_seen<=0;active<=0;samples_done<=0;block_done<=0;column<=0;row<=0;pixel_address<=0;block_address<=0;
  issued<=0;received<=0;recovery<=0;video_done<=0;column_phase<=6;row_phase<=5;cache_index<=0;
 end else begin
  job_sync<={job_sync[1:0],video_request};slot_meta<=video_slot;slot_sync<=slot_meta;
  cancel_meta<=video_cancel;cancel_sync<=cancel_meta;blank_meta<=video_blank;blank_sync<=blank_meta;
  // Advance only when this response contains the next exact sample. Other
  // words in the same burst are discarded; no image quality is reduced.
  if(write_sample)begin
   if(leave_block)block_done<=1;
   if(row==62 && column==111)samples_done<=1;
   else begin
    pixel_address<=pixel_address+pixel_step;cache_index<=cache_index+1'b1;
    if(column==111)begin
     column<=0;row<=row+1'b1;column_phase<=6;
     row_phase<=row_phase>=4 ? row_phase-3'd4:row_phase+3'd3;
    end else begin
     column<=column+1'b1;
     column_phase<=column_phase>=2 ? column_phase-3'd2:column_phase+3'd5;
    end
   end
  end
  case(state)
   IDLE:if(job_sync[2]!=job_seen)begin
    job_seen<=job_sync[2];active<=!cancel_sync;samples_done<=0;
    column<=0;row<=0;pixel_address<=base(slot_sync)+21'd3202;
    column_phase<=6;row_phase<=5;cache_index<=0;
    if(cancel_sync)video_done<=job_sync[2];
   end else if(active && cancel_sync)begin active<=0;video_done<=job_seen;end
   else if(request && init_done && !refresh && !busy && !frame_busy)begin
    state<=READ;issued<=0;received<=0;block_done<=0;block_address<=pixel_address[20:BW];
   end
   READ:begin
    if(read_command)issued<=issued+1'b1;
    if(response_valid)begin
     received<=received+1'b1;
     if(received==BURST_WORDS-1)begin state<=RECOVER;recovery<=0;end
    end
   end
   RECOVER:if(recovery==10)begin
    state<=IDLE;
    // A cancellation is acknowledged only after every issued response and
    // recovery clock drained. The source slot stays pinned until then.
    if(samples_done || cancel_sync)begin active<=0;video_done<=job_seen;end
   end else recovery<=recovery+1'b1;
   default:state<=IDLE;
  endcase
 end
endmodule

// 7056 RGB565 pixels: two 2048-pixel RAM32K banks, a 2048-pixel
// RAM9K bank (four blocks), and a 1024-pixel RAM9K bank (two blocks).
// No bit packing or color truncation; arbitrary reads take one video clock.
module photo_thumbnail_cache(
 input write_clk,write_enable,input [12:0] write_address,input [15:0] write_data,
 input read_clk,input [12:0] read_address,output [15:0] read_data
);
`ifdef THUMBNAIL_SIM
 reg [15:0] memory[0:7055];reg [15:0] q;
 always @(posedge write_clk)if(write_enable && write_address<7056)memory[write_address]<=write_data;
 always @(posedge read_clk)q<=read_address<7056 ? memory[read_address]:16'd0;
 assign read_data=q;
`else
 wire [15:0] bank_data[0:3];reg [1:0] bank;reg valid;
 always @(posedge read_clk)begin bank<=read_address[12:11];valid<=read_address<7056;end
 assign read_data=valid ? bank_data[bank]:16'd0;
 genvar b;
 generate for(b=0;b<4;b=b+1)begin:banks
 localparam AW=b==3 ? 10:11;
 localparam DEPTH=b==3 ? 1024:2048;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(AW),.DATA_DEPTH_A(DEPTH),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(AW),.DATA_DEPTH_B(DEPTH),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT(b<2 ? "32K":"9K")) ram(
 .clka(write_clk),.rsta(1'b0),.cea(1'b1),.wea(write_enable && write_address<7056 && write_address[12:11]==b),.ocea(1'b1),.bea(1'b0),
 .addra(write_address[AW-1:0]),.dia(write_data),.doa(),
 .clkb(read_clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(read_address[AW-1:0]),.dib(16'd0),.dob(bank_data[b]));
 end endgenerate
`endif
endmodule

// Whole-preview handshake: hold the source slot until completion or a
// safely acknowledged cancellation. New cache identities never show old RAM.
module photo_thumbnail_overlay #(parameter X=1088,Y=528,DELAY=1,SEPARATE_DISPLAY=0)(
 input clk,rst,frame_tick,enable,cache_valid,input [1:0] cache_slot,input [5:0] identity,
 input de,input [11:0] x,input [10:0] y,
 output reg request,output reg [1:0] slot,output cancel,
 input done,input [15:0] data,output [12:0] address,
 output visible,input [23:0] rgb_in,output [23:0] rgb_out,
 input display_enable,output read_busy
);
(* async_reg="true" *)reg [2:0] done_sync;
reg pending,cancel_pending,ready,armed;
reg [5:0] held;
wire eligible=enable && cache_valid && cache_slot<3;
wire changed=identity!=held;
assign cancel=cancel_pending || !eligible || (pending && changed);
wire show_allowed=!SEPARATE_DISPLAY || display_enable;
assign visible=armed && ready && eligible && !changed && show_allowed;
// The navigation guard above remains immediate. Pixel publication uses its
// registered copy: RAM cannot be rewritten until the cancel/done handshake,
// so clearing on the following clock cannot expose a partly replaced image.
reg pixel_visible;
always @(posedge clk or posedge rst)
 if(rst)pixel_visible<=0;else pixel_visible<=visible;
assign read_busy=pending || cancel_pending;
reg [6:0] source_x;reg [5:0] source_y;reg [3:0] phase_x,phase_y;reg [12:0] row_address;
wire advance_x=phase_x>=3;
wire [6:0] next_x=x==X-1 ? 7'd0:
 (x>=X && x<X+159 && advance_x ? source_x+7'd1:source_x);
assign address=row_address+next_x;
always @(posedge clk or posedge rst)
 if(rst)begin
  done_sync<=0;pending<=0;cancel_pending<=0;ready<=0;armed<=0;
  held<=0;request<=0;slot<=0;source_x<=0;source_y<=0;phase_x<=0;phase_y<=0;row_address<=0;
 end else begin
  done_sync<={done_sync[1:0],done};
  if(pending && (!eligible || changed))cancel_pending<=1;
  if(pending && done_sync[2]==request)begin
   pending<=0;cancel_pending<=0;ready<=eligible && !changed && !cancel_pending;
  end
  if(!pending && !ready && eligible)begin
   held<=identity;slot<=cache_slot;request<=!request;pending<=1;cancel_pending<=0;
  end
  if(!eligible || changed)begin ready<=0;armed<=0;end
  if(!show_allowed)armed<=0;
  if(frame_tick)armed<=ready && eligible && !changed && show_allowed;
  // Exact 7/10 increments map 112x63 to 160x90 without a pixel divider.
  if(x==X-1)begin source_x<=0;phase_x<=0;end
  else if(x>=X && x<X+159)begin
   phase_x<=phase_x>=3 ? phase_x-4'd3:phase_x+4'd7;
   if(advance_x)source_x<=source_x+1'b1;
  end
  if(x==1649)begin
   if(y==Y-1)begin source_y<=0;phase_y<=0;row_address<=0;end
   else if(y>=Y && y<Y+89)begin
    phase_y<=phase_y>=3 ? phase_y-4'd3:phase_y+4'd7;
    if(phase_y>=3)begin source_y<=source_y+1'b1;row_address<=row_address+13'd112;end
   end
  end
 end
wire image_area=de && x>=X && x<X+160 && y>=Y && y<Y+90;
wire panel=de && x>=X-2 && x<X+162 && y>=Y-14 && y<Y+92;
wire border=panel && (x<X || x>=X+160 || y>=Y+90 || y<Y-12);
wire heading=de && x>=X && x<X+160 && y>=Y-12 && y<Y;
wire [4:0] tx=x-X-4;wire [2:0] ty=y-Y+10;
reg [23:0] letters;
always @*case(ty)
 0:letters=24'b100010111110100010111110;
 1:letters=24'b110010100000010100001000;
 2:letters=24'b101010100000001000001000;
 3:letters=24'b100110111100001000001000;
 4:letters=24'b100010100000010100001000;
 5:letters=24'b100010100000100010001000;
 default:letters=24'b100010111110100010001000;
endcase
wire ink=heading && x>=X+4 && x<X+28 && y>=Y-10 && y<Y-3 && letters[23-tx];
wire [23:0] rgb={data[15:11],data[15:13],data[10:5],data[10:9],data[4:0],data[4:2]};
// Select the local colour before the single visibility gate. Explicit areas
// preserve clipped/edge layouts as well as the production right-side panel.
wire [23:0] panel_rgb=border ? 24'h52c4ff:heading ? (ink ? 24'hffffff:24'h10283c):rgb;
assign rgb_out=pixel_visible && (border || heading || image_area) ? panel_rgb:rgb_in;
endmodule
