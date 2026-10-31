`timescale 1ns/1ps
// B-only SPI transport: mutually exclusive response types share one word register.
module photo_audio_spi_b_offload #(parameter CATALOG_STATUS=0,EXTENDED_AV=0,PAGE_CUE=0,TYPED_PAGE=0,REMOTE_RELIEF=0,REMOTE_HMI=0)(
 input clk,rst,input spi_sclk,spi_cs,spi_mosi,output reg spi_miso,output packet_active,
 input catalog_complete,input [7:0] active_epoch,input [2:0] active_track,track_count,input switching,
 input [13:0] fifo_used,input [31:0] processed_pcm,input bg_enabled,output reg sample_prepare,output reg fifo_read,
 output reg request_valid,output reg [7:0] request_epoch,output reg [2:0] request_track,
 output reg request_bg,request_repair,output reg [3:0] request_volume,request_cue,
 output reg pcm_sent,av_snapshot,output [8:0] av_address,input [31:0] av_data,output reg [2:0] page_cue_count,output reg page_valid,output reg [3:0] page_style,input page_ready,
 input relief_ready,input [31:0] relief_descriptor,relief_data,output [8:0] relief_address,
 output reg relief_request,output reg [31:0] relief_query,
 input [31:0] hmi_session,hmi_header,input [95:0] hmi_payload,
 output reg [52:0] hmi_status,output hmi_enabled,
 output reg hmi_ack_valid,output reg [7:0] hmi_ack_token,output reg hmi_restart
);
reg spi_sclk_meta,sclk_sync,sclk_previous,spi_cs_meta,cs_sync,cs_previous;
reg spi_mosi_meta,mosi_sync;
always @(posedge clk or posedge rst)begin
 if(rst)begin spi_sclk_meta<=0;sclk_sync<=0;sclk_previous<=0;spi_cs_meta<=1;cs_sync<=1;cs_previous<=1;spi_mosi_meta<=0;mosi_sync<=0;end
 else begin spi_sclk_meta<=spi_sclk;sclk_sync<=spi_sclk_meta;sclk_previous<=sclk_sync;
  spi_cs_meta<=spi_cs;cs_sync<=spi_cs_meta;cs_previous<=cs_sync;spi_mosi_meta<=spi_mosi;mosi_sync<=spi_mosi_meta;end
end
assign packet_active=!cs_sync;
wire rise=sclk_sync && !sclk_previous,fall=!sclk_sync && sclk_previous;
reg [31:0] tx_shift,rx_shift;reg [5:0] bit_index;reg [8:0] word_index;
reg word_complete;reg [7:0] packet_epoch;reg [8:0] payload_words;
wire [31:0] received_word={rx_shift[30:0],mosi_sync};
wire can_send=!switching && (fifo_used>=128 || !bg_enabled) && packet_epoch==active_epoch && request_epoch==active_epoch;
reg relief_mode,relief_packet_valid;reg [31:0] relief_packet_descriptor;
reg hmi_mode;reg [31:0] hmi_lo,hmi_hi,hmi_peer,hmi_status_session;
reg hmi_lo_ok,hmi_reset_seen;
assign hmi_enabled=REMOTE_HMI && hmi_session!=0 && hmi_status_session==hmi_session;
reg hmi_check_pending,hmi_capture;
reg av_mode,control_only;reg [2:0] seen_page_seq,control_page_seq;
wire typed_word_ok=received_word[31:24]==8'hd8 && received_word[23:21]==control_page_seq && received_word[20:17]<=10 &&
 received_word[16:9]==0 && received_word[1:0]==0;
reg [31:0] prepared_word;
assign av_address=word_index-9'd1;
assign relief_address=word_index-9'd2;
// SPI words span hundreds of system clocks. Decode their ownership early,
// leaving only a shallow registered-word mux at the MISO output edge.
reg count_q,hmi_q,relief_q,relief_desc_q,av_q,pcm_q;
reg [31:0] count_reply;
always @(posedge clk or posedge rst)
 if(rst)begin count_q<=0;hmi_q<=0;relief_q<=0;relief_desc_q<=0;av_q<=0;pcm_q<=0;count_reply<=0;end
 else begin
  count_q<=word_index==1;
  hmi_q<=REMOTE_HMI && hmi_mode && word_index>=2 && word_index<=5;
  relief_q<=REMOTE_RELIEF && relief_mode && word_index>=2 && word_index<388;
  relief_desc_q<=word_index==2;
  av_q<=av_mode && word_index>=2 && word_index<292;
  pcm_q<=!av_mode && !relief_mode && word_index>=(hmi_mode ? 6:2) && word_index<2+payload_words;
  count_reply<=relief_mode ? (relief_packet_valid ? 32'd385:32'd0):av_mode ? 32'd290:control_only ? 32'd0:hmi_mode ? (can_send ? 32'd132:32'd4):can_send ? 32'd128:32'd0;
  

 end
// A packet selects exactly one of HMI, visualizer and relief responses.
// Prepare eight SPI bits before the word boundary, as in the original core.
always @(posedge clk or posedge rst)
 if(rst)prepared_word<=0;
 else if(!cs_sync && rise && bit_index==24)begin
  if(REMOTE_HMI && hmi_mode)case(word_index)
   1:prepared_word<=hmi_header;2:prepared_word<=hmi_payload[95:64];
   3:prepared_word<=hmi_payload[63:32];4:prepared_word<=hmi_payload[31:0];default:;
  endcase
  else if(REMOTE_RELIEF && relief_mode)prepared_word<=relief_data;
  else if(EXTENDED_AV && av_mode)prepared_word<=av_data;
 end
wire [31:0] status_word={8'hb6,active_epoch,(CATALOG_STATUS ? catalog_complete:1'b0),(PAGE_CUE ? {seen_page_seq,1'b1}:4'd0),track_count,5'd0,active_track};
always @(posedge clk or posedge rst)begin
 if(rst)begin hmi_check_pending<=0;hmi_capture<=0;hmi_mode<=0;hmi_lo<=0;hmi_hi<=0;hmi_peer<=0;hmi_lo_ok<=0;hmi_reset_seen<=0;
  hmi_status<=0;hmi_status_session<=0;hmi_ack_valid<=0;hmi_ack_token<=0;hmi_restart<=0;relief_mode<=0;relief_packet_valid<=0;relief_packet_descriptor<=0;relief_request<=0;relief_query<=0;spi_miso<=0;tx_shift<=0;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
  seen_page_seq<=0;control_page_seq<=0;page_valid<=0;page_style<=0;page_cue_count<=0;control_only<=0;packet_epoch<=0;payload_words<=0;av_mode<=0;pcm_sent<=0;av_snapshot<=0;fifo_read<=0;sample_prepare<=0;request_bg<=1;request_repair<=0;request_volume<=5;request_cue<=0;request_valid<=0;request_epoch<=0;request_track<=0;end
 else begin
  hmi_check_pending<=0;hmi_capture<=0;hmi_ack_valid<=0;hmi_restart<=0;
  if(hmi_check_pending)hmi_capture<=hmi_hi[0]==0;
  if(hmi_capture)begin
   hmi_status<={hmi_hi[31:11],hmi_lo};hmi_status_session<=hmi_peer;
   hmi_ack_valid<=hmi_hi[2];hmi_ack_token<=hmi_hi[10:3];
   hmi_restart<=hmi_hi[1] && !hmi_reset_seen;hmi_reset_seen<=hmi_hi[1];
  end
  relief_request<=0;page_valid<=0;page_cue_count<=0;fifo_read<=0;sample_prepare<=0;request_valid<=0;pcm_sent<=0;av_snapshot<=0;
  if(cs_previous && !cs_sync)begin
   tx_shift<=status_word;spi_miso<=1;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
   hmi_mode<=0;hmi_lo_ok<=0;relief_mode<=0;relief_packet_valid<=0;packet_epoch<=active_epoch;payload_words<=0;av_mode<=0;control_only<=0;
  end else if(cs_sync)begin spi_miso<=0;word_complete<=0;end
  else begin
   if(rise)begin
    rx_shift<=received_word;
        if(!av_mode && !relief_mode && bit_index==16 && (hmi_mode ? (payload_words==132 && word_index>=5 && word_index<133):(payload_words==128 && word_index>=1 && word_index<129)))begin fifo_read<=bg_enabled;sample_prepare<=1;end
    if(bit_index==31)begin
     bit_index<=0;word_index<=word_index+1'b1;word_complete<=1;
     if(REMOTE_HMI)begin
      if(word_index==0 && received_word[31:24]==8'haa)hmi_mode<=1;
      if(hmi_mode)case(word_index)
       1:hmi_lo<=received_word;
       2:hmi_hi<=received_word;
       3:hmi_peer<=received_word;
       4:hmi_lo_ok<=1'b1;
       5:hmi_check_pending<=1;
       default:;
      endcase
     end
     if(REMOTE_RELIEF && word_index==0 && received_word[31:24]==8'ha9)begin
      relief_mode<=1;relief_packet_valid<=relief_ready;relief_packet_descriptor<=relief_descriptor;
     end
     if(REMOTE_RELIEF && relief_mode && word_index==1)begin relief_request<=1;relief_query<=received_word;end
     if(EXTENDED_AV && word_index==0 && received_word[31:24]==8'ha7)begin av_mode<=1;av_snapshot<=1;end
     if(word_index==0 && (received_word[31:24]==8'ha6 || (REMOTE_HMI && received_word[31:24]==8'haa) || (PAGE_CUE && received_word[31:24]==8'ha8)))begin
      control_only<=PAGE_CUE && received_word[31:24]==8'ha8;control_page_seq<=received_word[3:1];
      request_valid<=1;request_epoch<=received_word[23:16];request_track<=received_word[10:8];request_bg<=received_word[15];request_repair<=received_word[0];request_volume<=received_word[14:11];request_cue<=received_word[7:4];
     end
     if(PAGE_CUE && !TYPED_PAGE && word_index==0 && (received_word[31:24]==8'ha6 || received_word[31:24]==8'ha7 || received_word[31:24]==8'ha8))begin
      page_cue_count<=received_word[3:1]-seen_page_seq;
      seen_page_seq<=received_word[3:1];
     end
     if(TYPED_PAGE && control_only && word_index==1 && typed_word_ok && control_page_seq!=seen_page_seq && page_ready)begin
      page_valid<=1;page_style<=received_word[20:17];seen_page_seq<=control_page_seq;
     end
    end else bit_index<=bit_index+1'b1;
   end
   if(fall)begin
    if(word_complete)begin
     word_complete<=0;
     if(count_q)begin payload_words<=count_reply[8:0];tx_shift<=count_reply;spi_miso<=count_reply[31];end
     else if(hmi_q)begin tx_shift<=prepared_word;spi_miso<=prepared_word[31];end
     else if(relief_q)begin
      tx_shift<=relief_desc_q ? relief_packet_descriptor:prepared_word;
      spi_miso<=relief_desc_q ? relief_packet_descriptor[31]:prepared_word[31];
     end else if(av_q)begin tx_shift<=prepared_word;spi_miso<=prepared_word[31];end
     else if(pcm_q)begin tx_shift<=processed_pcm;spi_miso<=processed_pcm[31];pcm_sent<=1;end
     else begin tx_shift<=0;spi_miso<=0;end
    end else begin spi_miso<=tx_shift[30];tx_shift<={tx_shift[30:0],1'b0};end
   end
  end
 end
end
endmodule
