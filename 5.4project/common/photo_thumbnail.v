// A static 64x36 RGB565 preview is generated from the accepted next-photo
// cache during vertical blanking. Five RAM9Ks retain it for 160x90 scanout.
module photo_thumbnail_memory(
 input clk,rst,init_done,refresh,busy,frame_busy,allow_access,other_request,
 output request,claim,read_command,output [20:0] address,
 input response_valid,input [31:0] response,
 input video_clk,video_request,video_cancel,video_blank,input [1:0] video_slot,
 output reg video_done,input [11:0] video_address,output [15:0] video_data
);
function [20:0] base;
 input [1:0] slot;
 begin case(slot)0:base=0;1:base=21'd691200;default:base=21'd1382400;endcase end
endfunction
localparam IDLE=0,READ=1,RECOVER=2;
reg [1:0] state;
(* async_reg="true" *)reg [2:0] job_sync;
(* async_reg="true" *)reg [1:0] slot_meta,slot_sync;
(* async_reg="true" *)reg cancel_meta,cancel_sync,blank_meta,blank_sync;
reg job_seen,active;
reg [5:0] column,row;
reg [20:0] pixel_address;
reg [2:0] issued;reg [1:0] received;reg [3:0] recovery;
// A row jump starts at its last sampled column: pitch - 63*step.
// One accumulator serves both columns and rows, without a second base register.
wire [20:0] pixel_step=column==63 ? 21'd12170:21'd10;
assign request=active && blank_sync && !cancel_sync && allow_access && !other_request;
assign claim=state!=IDLE;
assign read_command=state==READ && issued<4 && !refresh;
// Every owned turn is an aligned four-word burst. Upper bits never carry.
assign address={pixel_address[20:2],issued[1:0]};
wire write_sample=state==READ && response_valid && received==pixel_address[1:0];
wire [15:0] sample=response[31:16];
photo_thumbnail_cache cache(.write_clk(clk),.write_enable(write_sample),.write_address({row,column}),.write_data(sample),
 .read_clk(video_clk),.read_address(video_address),.read_data(video_data));
always @(posedge clk or posedge rst)
 if(rst)begin
  state<=IDLE;job_sync<=0;slot_meta<=0;slot_sync<=0;cancel_meta<=0;cancel_sync<=0;blank_meta<=0;blank_sync<=0;
  job_seen<=0;active<=0;column<=0;row<=0;pixel_address<=0;
  issued<=0;received<=0;recovery<=0;video_done<=0;
 end else begin
  job_sync<={job_sync[1:0],video_request};slot_meta<=video_slot;slot_sync<=slot_meta;
  cancel_meta<=video_cancel;cancel_sync<=cancel_meta;blank_meta<=video_blank;blank_sync<=blank_meta;
  case(state)
   IDLE:if(job_sync[2]!=job_seen)begin
    job_seen<=job_sync[2];active<=!cancel_sync;
    column<=0;row<=0;pixel_address<=base(slot_sync);
    if(cancel_sync)video_done<=job_sync[2];
   end else if(active && cancel_sync)begin active<=0;video_done<=job_seen;end
   else if(request && init_done && !refresh && !busy && !frame_busy)begin
    state<=READ;issued<=0;received<=0;
   end
   READ:begin
    if(read_command)issued<=issued+1'b1;
    if(response_valid)begin
     received<=received+1'b1;
     if(received==3)begin state<=RECOVER;recovery<=0;end
    end
   end
   RECOVER:if(recovery==10)begin
    state<=IDLE;
    if(row==35 && column==63)begin active<=0;video_done<=job_seen;end
    else begin
     pixel_address<=pixel_address+pixel_step;
     if(column==63)begin column<=0;row<=row+1'b1;end
     else column<=column+1'b1;
    end
   end else recovery<=recovery+1'b1;
   default:state<=IDLE;
  endcase
 end
endmodule

// 2048 + 256 pixels avoid rounding the entire 2304-pixel store to 4096.
// TD maps the simple dual-port 16-bit banks to four + one physical RAM9Ks.
module photo_thumbnail_cache(
 input write_clk,write_enable,input [11:0] write_address,input [15:0] write_data,
 input read_clk,input [11:0] read_address,output [15:0] read_data
);
`ifdef THUMBNAIL_SIM
 reg [15:0] memory[0:2303];reg [15:0] q;
 always @(posedge write_clk)if(write_enable)memory[write_address]<=write_data;
 always @(posedge read_clk)q<=read_address<2304 ? memory[read_address]:16'd0;
 assign read_data=q;
`else
 wire [15:0] main_data,tail_data;reg bank;
 always @(posedge read_clk)bank<=read_address[11];
 assign read_data=bank ? tail_data:main_data;
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(11),.DATA_DEPTH_A(2048),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(11),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) main_ram(
 .clka(write_clk),.rsta(1'b0),.cea(1'b1),.wea(write_enable && !write_address[11]),.ocea(1'b1),.bea(1'b0),
 .addra(write_address[10:0]),.dia(write_data),.doa(),
 .clkb(read_clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(read_address[10:0]),.dib(16'd0),.dob(main_data));
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.ADDR_WIDTH_A(8),.DATA_DEPTH_A(256),
 .DATA_WIDTH_B(16),.ADDR_WIDTH_B(8),.DATA_DEPTH_B(256),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
 .RESETMODE("SYNC"),.IMPLEMENT("9K")) tail_ram(
 .clka(write_clk),.rsta(1'b0),.cea(1'b1),.wea(write_enable && write_address[11]),.ocea(1'b1),.bea(1'b0),
 .addra(write_address[7:0]),.dia(write_data),.doa(),
 .clkb(read_clk),.rstb(1'b0),.ceb(1'b1),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(read_address[7:0]),.dib(16'd0),.dob(tail_data));
`endif
endmodule

// Whole-preview handshake: hold the source slot until completion or a
// safely acknowledged cancellation. New cache identities never show old RAM.
module photo_thumbnail_overlay #(parameter X=1088,Y=528,DELAY=1)(
 input clk,rst,frame_tick,enable,cache_valid,input [1:0] cache_slot,input [5:0] identity,
 input de,input [11:0] x,input [10:0] y,
 output reg request,output reg [1:0] slot,output cancel,
 input done,input [15:0] data,output [11:0] address,
 output visible,input [23:0] rgb_in,output [23:0] rgb_out
);
(* async_reg="true" *)reg [2:0] done_sync;
reg pending,cancel_pending,ready,armed;
reg [5:0] held;
wire eligible=enable && cache_valid && cache_slot<3;
wire changed=identity!=held;
assign cancel=cancel_pending || !eligible || (pending && changed);
assign visible=armed && ready && eligible && !changed;
reg [5:0] source_x,source_y;reg [2:0] phase_x,phase_y;
wire advance_x=phase_x==2 || phase_x==4;
wire [5:0] next_x=x==X-1 ? 6'd0:
 (x>=X && x<X+159 && advance_x ? source_x+6'd1:source_x);
assign address={source_y,next_x};
always @(posedge clk or posedge rst)
 if(rst)begin
  done_sync<=0;pending<=0;cancel_pending<=0;ready<=0;armed<=0;
  held<=0;request<=0;slot<=0;source_x<=0;source_y<=0;phase_x<=0;phase_y<=0;
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
  if(frame_tick)armed<=ready && eligible && !changed;
  // Exact 2/5 source-coordinate increments: three then two display pixels
  // per sample. Counters replace division and retain the 16:9 aspect ratio.
  if(x==X-1)begin source_x<=0;phase_x<=0;end
  else if(x>=X && x<X+159)begin
   phase_x<=phase_x==4 ? 3'd0:phase_x+1'b1;
   if(advance_x)source_x<=source_x+1'b1;
  end
  if(x==1649)begin
   if(y==Y-1)begin source_y<=0;phase_y<=0;end
   else if(y>=Y && y<Y+89)begin
    phase_y<=phase_y==4 ? 3'd0:phase_y+1'b1;
    if(phase_y==2 || phase_y==4)source_y<=source_y+1'b1;
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
assign rgb_out=visible && border ? 24'h52c4ff:visible && ink ? 24'hffffff:
 visible && heading ? 24'h10283c:visible && image_area ? rgb:rgb_in;
endmodule
