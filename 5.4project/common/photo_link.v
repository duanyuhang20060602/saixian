`timescale 1ns/1ps
module photo_link_sender #(parameter FRAME_PIXELS=921600,PREP_CYCLES=2,ENABLE_CRC=0,LEGACY_TIMING=1,AWARD_TAIL=0,PREFETCH_WORD=0)(
 input award_frame,input clk,rst,start,abort,extended_frame,
 output reg plane_start,output reg effect_plane,input [31:0] data,input empty,read_ack,link_ready,
 output reg read_req,output read_en,
 output reg [15:0] link_data,output reg link_valid,link_sof,link_eof,
 output reg done,output busy,output [31:0] frame_crc
);
function [31:0] crc_pixel;
 input [31:0] c;input [15:0] pixel;reg [31:0] t;integer i;
 begin t=c^{24'd0,pixel[15:8]};for(i=0;i<8;i=i+1)t=(t>>1)^(t[0] ? 32'hedb88320:0);
 t=t^{24'd0,pixel[7:0]};for(i=0;i<8;i=i+1)t=(t>>1)^(t[0] ? 32'hedb88320:0);crc_pixel=t;end
endfunction
localparam IDLE=0,REQUEST=1,DRAIN=2,FETCH=3,LATCH=4,HIGH=5,LOW=6,FINISH=7,PRE_HIGH=8,PRE_LOW=9;
reg frame_extended;wire [20:0] final_index=frame_extended ? 21'd1382398:FRAME_PIXELS-2;
reg [3:0] state;reg [2:0] prep_count;reg [20:0] index;reg [31:0] word_data,crc;
reg ack_meta,ack_sync;reg [2:0] settle;
reg [31:0] prefetched_data;reg prefetch_pending,prefetch_valid;
wire plane_boundary=frame_extended && !(AWARD_TAIL && award_frame) && !effect_plane && index==FRAME_PIXELS-2;
// One elastic word overlaps the source's synchronous read with transmission.
// Never read beyond a frame or the native/auxiliary-plane transaction boundary.
wire prefetch_read=PREFETCH_WORD && !abort && state==HIGH && link_valid && link_ready &&
                   index!=final_index && !plane_boundary && !empty;
assign read_en=(state==FETCH && !empty) || prefetch_read;
assign busy=state!=IDLE;assign frame_crc=ENABLE_CRC ? ~crc:32'd0;
always @(posedge clk or posedge rst)begin
 if(rst)begin plane_start<=0;effect_plane<=0;frame_extended<=0;state<=IDLE;prep_count<=0;index<=0;word_data<=0;read_req<=0;done<=0;crc<=32'hffffffff;ack_meta<=0;ack_sync<=0;settle<=0;prefetched_data<=0;prefetch_pending<=0;prefetch_valid<=0;end
 else begin
  ack_meta<=read_ack;ack_sync<=ack_meta;done<=0;plane_start<=0;
  if(prefetch_pending)begin prefetched_data<=data;prefetch_pending<=0;prefetch_valid<=1;end
  if(abort)begin state<=IDLE;read_req<=0;prefetch_pending<=0;prefetch_valid<=0;end
  else case(state)
   IDLE:if(start)begin effect_plane<=0;frame_extended<=extended_frame || (AWARD_TAIL && award_frame);read_req<=1;index<=0;crc<=32'hffffffff;prefetch_pending<=0;prefetch_valid<=0;state<=REQUEST;end
   REQUEST:if(ack_sync)begin read_req<=0;settle<=0;state<=DRAIN;end
   DRAIN:if(!ack_sync)begin if(settle==4)state<=FETCH;else settle<=settle+1'b1;end
   FETCH:if(!empty)state<=LATCH;
   // Launch the pixel while valid is low and let it settle for two full
   // clocks. The previously verified builtin sender also separates pixel
   // preparation from valid; adjacent high/low launches had only half a
   // clock for the external data wires to settle.
   LATCH:begin word_data<=data;prep_count<=0;state<=LEGACY_TIMING ? HIGH:PRE_HIGH;end
   PRE_HIGH:if(prep_count==PREP_CYCLES)state<=HIGH;else prep_count<=prep_count+1'b1;
   HIGH:if(link_valid && link_ready)begin if(ENABLE_CRC)crc<=crc_pixel(crc,word_data[31:16]);if(prefetch_read)prefetch_pending<=1;prep_count<=0;state<=LEGACY_TIMING ? LOW:PRE_LOW;end
   PRE_LOW:if(prep_count==PREP_CYCLES)state<=LOW;else prep_count<=prep_count+1'b1;
   LOW:if(link_valid && link_ready)begin
    if(ENABLE_CRC)crc<=crc_pixel(crc,word_data[15:0]);
    if(index==final_index)state<=FINISH;
    else if(plane_boundary)begin
     index<=index+2;effect_plane<=1;plane_start<=1;read_req<=1;state<=REQUEST;
    end else begin
     index<=index+2;
     if(PREFETCH_WORD && (prefetch_pending || prefetch_valid))begin
      word_data<=prefetch_pending ? data:prefetched_data;
      prefetch_valid<=0;prep_count<=0;state<=LEGACY_TIMING ? HIGH:PRE_HIGH;
     end else state<=FETCH;
    end
   end
   FINISH:begin done<=1;state<=IDLE;end
   default:state<=IDLE;
  endcase
 end
end
always @(negedge clk or posedge rst)begin
 if(rst)begin link_data<=0;link_valid<=0;link_sof<=0;link_eof<=0;end
 else begin
  link_valid<=!abort && (state==HIGH || state==LOW);
  if(LEGACY_TIMING)link_data<=state==LOW ? word_data[15:0]:word_data[31:16];
  else if(state==LOW || state==PRE_LOW)link_data<=word_data[15:0];
  else if(state==HIGH || state==PRE_HIGH)link_data<=word_data[31:16];
  link_sof<=state==HIGH && index==0;link_eof<=state==LOW && index==final_index;
 end
end
endmodule

module photo_link_receiver #(parameter FRAME_PIXELS=921600,ENABLE_CRC=0,LEGACY_TIMING=1,AWARD_TAIL=0)(
 input award_frame,input clk,rst,arm,abort,extended_frame,input [15:0] data,input valid,sof,eof,
 output ready,output armed,output busy,
 output reg write_req,input write_ack,full,output reg write_en,output reg [31:0] write_data,
 input finish_toggle,output reg done,output reg fault,output [31:0] frame_crc,
 output reg [3:0] fault_detail
);
function [31:0] crc_pixel;
 input [31:0] c;input [15:0] pixel;reg [31:0] t;integer i;
 begin t=c^{24'd0,pixel[15:8]};for(i=0;i<8;i=i+1)t=(t>>1)^(t[0] ? 32'hedb88320:0);
 t=t^{24'd0,pixel[7:0]};for(i=0;i<8;i=i+1)t=(t>>1)^(t[0] ? 32'hedb88320:0);crc_pixel=t;end
endfunction
localparam IDLE=0,REQUEST=1,DRAIN=2,RECEIVE=3,WAIT_WRITE=4,ERROR=5;
reg frame_extended;wire [20:0] final_count=frame_extended ? 21'd1382399:FRAME_PIXELS-1;
reg [2:0] state;reg [20:0] count;reg [15:0] first;reg [31:0] crc;
reg ack_meta,ack_sync,fin_meta,fin_sync,fin_seen;reg [2:0] settle;
reg ready_reg;
// Return a registered ready on the falling edge, so it has half a clock
// to reach B before its rising-edge decision. A uses that same advertised
// permission at the following rising edge; a pending word can be held full.
always @(negedge clk or posedge rst)
 if(rst)ready_reg<=0;else ready_reg<=state==RECEIVE && !full && !write_en;
assign ready=LEGACY_TIMING ? (state==RECEIVE && !full && !write_en):ready_reg;
assign armed=state==RECEIVE;assign busy=state!=IDLE;assign frame_crc=ENABLE_CRC ? ~crc:32'd0;
always @(posedge clk or posedge rst)begin
 if(rst)begin frame_extended<=0;state<=IDLE;count<=0;first<=0;crc<=32'hffffffff;write_req<=0;write_en<=0;write_data<=0;done<=0;fault<=0;fault_detail<=0;ack_meta<=0;ack_sync<=0;fin_meta<=0;fin_sync<=0;fin_seen<=0;settle<=0;end
 else begin
  ack_meta<=write_ack;ack_sync<=ack_meta;fin_meta<=finish_toggle;fin_sync<=fin_meta;
  done<=0;write_en<=write_en && full;
  if(abort)begin state<=IDLE;write_req<=0;fault<=0;end
  else case(state)
   IDLE:if(arm)begin frame_extended<=extended_frame || (AWARD_TAIL && award_frame);write_req<=1;count<=0;crc<=32'hffffffff;fault<=0;fault_detail<=0;fin_seen<=fin_sync;state<=REQUEST;end
   REQUEST:if(ack_sync)begin write_req<=0;settle<=0;state<=DRAIN;end
   DRAIN:if(!ack_sync)begin if(settle==4)state<=RECEIVE;else settle<=settle+1'b1;end
   RECEIVE:if(valid && ready)begin
    if(sof!=(count==0) || eof!=(count==final_count))begin
     fault<=1;state<=ERROR;
     // 1 missing SOF, 2 repeated SOF, 3 early EOF, 4 missing EOF.
     fault_detail<=sof!=(count==0) ? (count==0 ? 4'd1:4'd2) : (count==final_count ? 4'd4:4'd3);
    end
    else begin
     if(ENABLE_CRC)crc<=crc_pixel(crc,data);
     if(!count[0])first<=data;else begin write_data<={first,data};write_en<=1;end
     count<=count+1'b1;
     if(count==final_count)state<=WAIT_WRITE;
    end
   end
   WAIT_WRITE:if(fin_sync!=fin_seen)begin done<=1;state<=IDLE;end
   ERROR:begin fault<=1;write_req<=0;end
   default:state<=IDLE;
  endcase
 end
end
endmodule

// Bundled-data event: payload must be held until the downstream transaction
// finishes. The two-flop toggle synchronizer provides the settling interval.
module photo_event_sync(input clk,rst,input toggle,output pulse);
reg event_meta,event_sync,event_seen;
assign pulse=event_sync!=event_seen;
always @(posedge clk or posedge rst)
 if(rst)begin event_meta<=0;event_sync<=0;event_seen<=0;end
 else begin event_meta<=toggle;event_sync<=event_meta;event_seen<=event_sync;end
endmodule
