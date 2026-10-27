`timescale 1ns/1ps
// Small typed FIFO in registers/distributed RAM; A uses four entries, B eight.
module photo_page_type_queue #(parameter AW=3)(input clk,rst,push,input [3:0] style_in,input pop,
 output valid,full,output [3:0] style_out,output reg overflow);
reg [3:0] styles[0:(1<<AW)-1];reg [AW-1:0] wp,rp;reg [AW:0] used;
assign valid=used!=0;assign full=used==(1<<AW);assign style_out=styles[rp];
wire take=pop && valid,put=push && (!full || take);
always @(posedge clk)if(put)styles[wp]<=style_in;
always @(posedge clk or posedge rst)begin
 if(rst)begin wp<=0;rp<=0;used<=0;overflow<=0;end
 else begin
  if(put)wp<=wp+1'b1;if(take)rp<=rp+1'b1;
  if(push && !put)overflow<=1;
  case({put,take})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
 end
end
endmodule

// Both ends run from their system clocks. SPI pins are oversampled; no
// fabric-generated clock clocks internal logic. Mode 0, MSB first.
module photo_audio_fifo #(parameter DEPTH=8192,AW=13,RAM32_HEAD=0)(
 input clk,rst,input write_en,input [31:0] write_data,input read_en,
 output [31:0] data,output empty,full,output reg [AW:0] used
);
reg [AW-1:0] wp,rp;
wire push=write_en && !full,pop=read_en && !empty;
assign empty=used==0;assign full=used==DEPTH;
generate if(RAM32_HEAD==0)begin: inferred
 reg [31:0] memory[0:DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
 reg [31:0] q;
 always @(posedge clk)begin if(push)memory[wp]<=write_data;if(pop)q<=memory[rp];end
 assign data=q;
end else if(RAM32_HEAD==DEPTH)begin: all_ram32
 photo_audio_word_ram #(.ADDR(AW),.IMPLEMENT("32K")) memory(
 .clk(clk),.we(push),.wa(wp),.wd(write_data),.re(pop),.ra(rp),.rd(data));
end else begin: hybrid
 // Equal halves avoid wide address subtraction. Keep all 8192 PCM samples.
 wire [31:0] head_q,tail_q;reg read_tail;
 always @(posedge clk)if(pop)read_tail<=rp[AW-1];
 photo_audio_word_ram #(.ADDR(AW-1),.IMPLEMENT("32K")) head(
 .clk(clk),.we(push && !wp[AW-1]),.wa(wp[AW-2:0]),.wd(write_data),
 .re(pop && !rp[AW-1]),.ra(rp[AW-2:0]),.rd(head_q));
 photo_audio_word_ram #(.ADDR(AW-1),.IMPLEMENT("9K")) tail(
 .clk(clk),.we(push && wp[AW-1]),.wa(wp[AW-2:0]),.wd(write_data),
 .re(pop && rp[AW-1]),.ra(rp[AW-2:0]),.rd(tail_q));
 assign data=read_tail ? tail_q:head_q;
end endgenerate
always @(posedge clk or posedge rst)begin
 if(rst)begin wp<=0;rp<=0;used<=0;end
 else begin
  if(push)wp<=wp+1'b1;if(pop)rp<=rp+1'b1;
  case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
 end
end
endmodule

module photo_audio_word_ram #(parameter ADDR=10,IMPLEMENT="9K")(
 input clk,we,input [ADDR-1:0] wa,input [31:0] wd,
 input re,input [ADDR-1:0] ra,output [31:0] rd);
`ifdef VICTORY_SIM
`define PHOTO_AUDIO_RAM_MODEL
`endif
`ifdef ERAM_SIM
`define PHOTO_AUDIO_RAM_MODEL
`endif
`ifdef PHOTO_AUDIO_RAM_MODEL
reg [31:0] memory[0:(1<<ADDR)-1];reg [31:0] q;
always @(posedge clk)begin if(we)memory[wa]<=wd;if(re)q<=memory[ra];end
assign rd=q;
`undef PHOTO_AUDIO_RAM_MODEL
`else
EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.ADDR_WIDTH_A(ADDR),.DATA_DEPTH_A(1<<ADDR),
 .DATA_WIDTH_B(32),.ADDR_WIDTH_B(ADDR),.DATA_DEPTH_B(1<<ADDR),.BYTE_ENABLE(0),
 .MODE("PDPW"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT(IMPLEMENT)) memory(
 .clka(clk),.rsta(1'b0),.cea(1'b1),.wea(we),.ocea(1'b1),.bea(1'b0),.addra(wa),.dia(wd),.doa(),
 .clkb(clk),.rstb(1'b0),.ceb(re),.web(1'b0),.oceb(1'b1),.beb(1'b0),.addrb(ra),.dib(32'd0),.dob(rd));
`endif
endmodule

module photo_audio_spi_b #(parameter CATALOG_STATUS=0,EXTENDED_AV=0,PAGE_CUE=0,TYPED_PAGE=0,REMOTE_RELIEF=0,REMOTE_HMI=0)(
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
 received_word[16:9]==0 && received_word[8:6]==~received_word[23:21] && received_word[5:2]==~received_word[20:17] && received_word[1:0]==0;
reg [31:0] av_prepared,av_crc;
assign av_address=word_index-9'd1;
assign relief_address=word_index-9'd2;
function [31:0] av_crc_bit;
 input [31:0] c;input b;
 begin av_crc_bit={c[30:0],1'b0}^((c[31]^b) ? 32'h04c11db7:32'd0);end
endfunction
// SPI words span hundreds of system clocks. Decode their ownership early,
// leaving only a shallow registered-word mux at the MISO output edge.
reg count_q,hmi_q,hmi_crc_q,relief_q,relief_crc_q,relief_desc_q,av_q,av_crc_q,pcm_q;
reg [31:0] count_reply,crc_reply,hmi_prepared;
always @(posedge clk or posedge rst)
 if(rst)begin count_q<=0;hmi_q<=0;hmi_crc_q<=0;relief_q<=0;relief_crc_q<=0;relief_desc_q<=0;av_q<=0;av_crc_q<=0;pcm_q<=0;count_reply<=0;crc_reply<=0;hmi_prepared<=0;end
 else begin
  count_q<=word_index==1;
  hmi_q<=REMOTE_HMI && hmi_mode && word_index>=2 && word_index<=6;hmi_crc_q<=word_index==6;
  relief_q<=REMOTE_RELIEF && relief_mode && word_index>=2 && word_index<388;
  relief_crc_q<=word_index==387;relief_desc_q<=word_index==2;
  av_q<=av_mode && word_index>=2 && word_index<293;av_crc_q<=word_index==292;
  pcm_q<=!av_mode && !relief_mode && word_index>=(hmi_mode ? 7:2) && word_index<2+payload_words;
  count_reply<=relief_mode ? (relief_packet_valid ? 32'd386:32'd0):av_mode ? 32'd291:control_only ? 32'd0:hmi_mode ? (can_send ? 32'd133:32'd5):can_send ? 32'd128:32'd0;
  crc_reply<=~av_crc;
  if(rise && hmi_mode && bit_index==24)case(word_index)
   1:hmi_prepared<=hmi_header;2:hmi_prepared<=hmi_payload[95:64];
   3:hmi_prepared<=hmi_payload[63:32];4:hmi_prepared<=hmi_payload[31:0];default:;
  endcase
 end
wire [31:0] status_word={8'hb6,active_epoch,(CATALOG_STATUS ? catalog_complete:1'b0),(PAGE_CUE ? {seen_page_seq,1'b1}:4'd0),track_count,5'd0,active_track};
always @(posedge clk or posedge rst)begin
 if(rst)begin hmi_check_pending<=0;hmi_capture<=0;hmi_mode<=0;hmi_lo<=0;hmi_hi<=0;hmi_peer<=0;hmi_lo_ok<=0;hmi_reset_seen<=0;
  hmi_status<=0;hmi_status_session<=0;hmi_ack_valid<=0;hmi_ack_token<=0;hmi_restart<=0;relief_mode<=0;relief_packet_valid<=0;relief_packet_descriptor<=0;relief_request<=0;relief_query<=0;spi_miso<=0;tx_shift<=0;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
  seen_page_seq<=0;control_page_seq<=0;page_valid<=0;page_style<=0;page_cue_count<=0;control_only<=0;packet_epoch<=0;payload_words<=0;av_mode<=0;av_prepared<=0;av_crc<=32'hffffffff;pcm_sent<=0;av_snapshot<=0;fifo_read<=0;sample_prepare<=0;request_bg<=1;request_repair<=0;request_volume<=5;request_cue<=0;request_valid<=0;request_epoch<=0;request_track<=0;end
 else begin
  hmi_check_pending<=0;hmi_capture<=0;hmi_ack_valid<=0;hmi_restart<=0;
  if(hmi_check_pending)hmi_capture<=hmi_lo_ok && rx_shift==~hmi_hi && hmi_peer==hmi_session && hmi_session!=0 && hmi_hi[0]==0;
  if(hmi_capture)begin
   hmi_status<={hmi_hi[31:11],hmi_lo};hmi_status_session<=hmi_peer;
   hmi_ack_valid<=hmi_hi[2];hmi_ack_token<=hmi_hi[10:3];
   hmi_restart<=hmi_hi[1] && !hmi_reset_seen;hmi_reset_seen<=hmi_hi[1];
  end
  relief_request<=0;page_valid<=0;page_cue_count<=0;fifo_read<=0;sample_prepare<=0;request_valid<=0;pcm_sent<=0;av_snapshot<=0;
  if(cs_previous && !cs_sync)begin
   tx_shift<=status_word;spi_miso<=1;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
   hmi_mode<=0;hmi_lo_ok<=0;relief_mode<=0;relief_packet_valid<=0;packet_epoch<=active_epoch;payload_words<=0;av_mode<=0;control_only<=0;av_crc<=32'hffffffff;
  end else if(cs_sync)begin spi_miso<=0;word_complete<=0;end
  else begin
   if(rise)begin
    rx_shift<=received_word;
    if((REMOTE_HMI && hmi_mode && word_index>=2 && word_index<6) || (EXTENDED_AV && av_mode && word_index>=2 && word_index<292) || (REMOTE_RELIEF && relief_mode && word_index>=2 && word_index<387))av_crc<=av_crc_bit(av_crc,spi_miso);
    if(EXTENDED_AV && av_mode && bit_index==24)av_prepared<=av_data;
    if(REMOTE_RELIEF && relief_mode && bit_index==24)av_prepared<=relief_data;
        if(!av_mode && !relief_mode && bit_index==16 && (hmi_mode ? (payload_words==133 && word_index>=6 && word_index<134):(payload_words==128 && word_index>=1 && word_index<129)))begin fifo_read<=bg_enabled;sample_prepare<=1;end
    if(bit_index==31)begin
     bit_index<=0;word_index<=word_index+1'b1;word_complete<=1;
     if(REMOTE_HMI)begin
      if(word_index==0 && received_word[31:24]==8'haa)hmi_mode<=1;
      if(hmi_mode)case(word_index)
       1:hmi_lo<=received_word;
       2:hmi_hi<=received_word;
       3:hmi_peer<=received_word;
       4:hmi_lo_ok<=received_word==~hmi_lo;
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
     else if(hmi_q)begin tx_shift<=hmi_crc_q ? crc_reply:hmi_prepared;spi_miso<=hmi_crc_q ? crc_reply[31]:hmi_prepared[31];end
     else if(relief_q)begin
      tx_shift<=relief_crc_q ? crc_reply:relief_desc_q ? relief_packet_descriptor:av_prepared;
      spi_miso<=relief_crc_q ? crc_reply[31]:relief_desc_q ? relief_packet_descriptor[31]:av_prepared[31];
     end else if(av_q)begin tx_shift<=av_crc_q ? crc_reply:av_prepared;spi_miso<=av_crc_q ? crc_reply[31]:av_prepared[31];end
     else if(pcm_q)begin tx_shift<=processed_pcm;spi_miso<=processed_pcm[31];pcm_sent<=1;end
     else begin tx_shift<=0;spi_miso<=0;end
    end else begin spi_miso<=tx_shift[30];tx_shift<={tx_shift[30:0],1'b0};end
   end
  end
 end
end
endmodule

module photo_audio_spi_a #(parameter CLK_HZ=75000000,HALF_DIV=10,STARTUP_SYNC=0,FIFO_AW=13,EXTENDED_AV=0,FIFO_RAM32_HEAD=0,PAGE_CUE=0,TYPED_PAGE=0,REMOTE_RELIEF=0,REMOTE_HMI=0,REMOTE_RESULT=0)(
 input clk,rst,next_track,bg_enable,repair_enable,playback_hold,input [3:0] volume,cue_event,input spi_miso,output reg spi_sclk,spi_cs,spi_mosi,
 output buffer_ready,output reg catalog_complete,output reg [2:0] track_count,track_index,output reg [7:0] desired_epoch,
 output reg sample_valid,output reg [23:0] audio_left,audio_right,
 output reg [15:0] packet_errors,underflows,
 output [3:0] diagnostic_stage,buffer_level,output reg header_seen,pcm_seen,nonzero_seen,
 input av_available,output reg av_begin,av_word_valid,av_commit,av_finish,
 output reg [8:0] av_word_index,output reg [31:0] av_word,
 output reg [31:0] play_position,output stream_reset,input page_event,input [3:0] page_style,
 input relief_enable,relief_available,input [31:0] relief_descriptor,
 output reg relief_begin,relief_word_valid,relief_commit,relief_finish,relief_sent,
 output reg [31:0] relief_sent_descriptor,relief_word,output reg [8:0] relief_word_index,
 input relief_sink_ready,input [52:0] hmi_status,input [31:0] hmi_session,input hmi_ack_valid,hmi_reset_request,input [7:0] hmi_ack_token,
 output reg hmi_begin,hmi_word_valid,hmi_commit,output reg [1:0] hmi_word_index,output reg [31:0] hmi_word
);
reg spi_miso_meta,miso_sync;
always @(posedge clk or posedge rst)begin
 if(rst)begin spi_miso_meta<=0;miso_sync<=0;end
 else begin spi_miso_meta<=spi_miso;miso_sync<=spi_miso_meta;end
end
wire change_track=next_track && track_count>1;
reg sent_bg;reg [3:0] sent_volume,sent_cue;
// Sequence changes request a control-only poll; they never reset PCM state.
reg [2:0] page_seq,page_ack;
reg page_inflight;reg typed_control_packet;reg typed_control_due;reg [3:0] packet_style;
wire [31:0] page_word={8'hd8,page_seq,packet_style,8'd0,~page_seq,~packet_style,2'd0};
wire typed_valid,typed_full,typed_pop;wire [3:0] typed_head;
photo_page_type_queue #(.AW(2)) outgoing_pages(.clk(clk),.rst(rst),.push(TYPED_PAGE && page_event),.style_in(page_style),
 .pop(typed_pop),.valid(typed_valid),.full(typed_full),.style_out(typed_head),.overflow());
wire page_waiting=TYPED_PAGE ? typed_valid:PAGE_CUE && page_seq!=page_ack;
wire send_page=page_waiting && (!TYPED_PAGE || typed_control_due);
wire [2:0] outgoing_seq=TYPED_PAGE && !page_inflight ? page_seq+3'd1:page_seq;
wire typed_launch;
always @(posedge clk or posedge rst)
 if(rst)page_seq<=0;
 else if(TYPED_PAGE ? typed_launch && !page_inflight:PAGE_CUE && page_event)page_seq<=page_seq+1'b1;
wire change_control=volume!=sent_volume || bg_enable!=sent_bg || cue_event!=0;
wire change_audio=change_track || change_control;
wire fifo_rst=rst || change_audio;
wire [31:0] fifo_data;wire fifo_empty,fifo_full;wire [FIFO_AW:0] fifo_used;
assign stream_reset=change_audio;
reg fifo_write;reg [31:0] fifo_input;
reg sample_ready,read_pending;reg [31:0] sample_word;
wire fifo_read=!sample_ready && !read_pending && !fifo_empty;
photo_audio_fifo #(.DEPTH(1<<FIFO_AW),.AW(FIFO_AW),.RAM32_HEAD(FIFO_RAM32_HEAD)) fifo(.clk(clk),.rst(fifo_rst),.write_en(fifo_write && !change_audio),.write_data(fifo_input),
 .read_en(fifo_read && !change_audio),.data(fifo_data),.empty(fifo_empty),.full(fifo_full),.used(fifo_used));
// V4 port: divide the rational 48 kHz phase by its compile-time GCD.
// The sample edge and phase lifetime remain identical, including track changes.
function integer rate_gcd;
 input integer a,b;integer remainder;
 begin while(b!=0)begin remainder=a%b;a=b;b=remainder;end rate_gcd=a;end
endfunction
localparam RATE_GCD=rate_gcd(CLK_HZ,48000);
localparam RATE_MOD=CLK_HZ/RATE_GCD,RATE_STEP=48000/RATE_GCD;
localparam RATE_BITS=($clog2(RATE_MOD)>0) ? $clog2(RATE_MOD):1;
reg [RATE_BITS-1:0] sample_phase;reg playing;
wire held=STARTUP_SYNC && playback_hold;
assign buffer_ready=sample_ready && fifo_used>=511;
wire sample_tick=sample_phase>=RATE_MOD-RATE_STEP;
assign buffer_level=fifo_used>>(FIFO_AW-3);
assign diagnostic_stage=!header_seen ? 4'd1:track_count==0 ? 4'd2:!pcm_seen ? 4'd3:
 !playing ? 4'd4:underflows!=0 ? 4'd6:4'd5;
always @(posedge clk or posedge rst)begin
 if(rst)begin sample_phase<=0;sample_valid<=0;audio_left<=0;audio_right<=0;
  sample_ready<=0;read_pending<=0;sample_word<=0;playing<=0;underflows<=0;play_position<=0;end
 else begin
  sample_valid<=sample_tick;
  sample_phase<=sample_tick ? sample_phase-(RATE_MOD-RATE_STEP):sample_phase+RATE_STEP;
  if(change_audio)begin play_position<=0;sample_ready<=0;read_pending<=0;playing<=0;audio_left<=0;audio_right<=0;underflows<=0;end
  else begin
   read_pending<=fifo_read;
   if(read_pending)begin sample_word<=fifo_data;sample_ready<=1;end
   if(!playing && (fifo_used>=512 || (STARTUP_SYNC && buffer_ready)))playing<=1;
   if(sample_tick)begin
    if(!held && playing && sample_ready)begin audio_left<={sample_word[15:0],8'd0};audio_right<={sample_word[31:16],8'd0};sample_ready<=0;play_position<=play_position+1'b1;end
    else begin audio_left<=0;audio_right<=0;if(!held && playing && underflows!=16'hffff)underflows<=underflows+1'b1;end
   end
  end
 end
end
localparam IDLE=0,TRANSFER=1;
reg [1:0] state;reg [3:0] divider;reg [16:0] idle_wait;
assign typed_launch=TYPED_PAGE && !change_audio && state==IDLE && idle_wait==0 && send_page;
reg [31:0] tx_shift,rx_shift;reg [5:0] bit_index;reg [8:0] word_index,payload_words;
reg finishing,header_magic,header_match;
reg hmi_transfer;reg [63:0] hmi_snapshot;
reg relief_transfer;reg [31:0] relief_query_hold;
reg av_transfer;reg [3:0] meta_cadence;reg [31:0] rx_av_crc;
// During boot the sample consumer is held. Do not require six additional
// PCM polls after its FIFO fills: that would deadlock asset/boot readiness.
wire boot_asset=REMOTE_RESULT && relief_enable && relief_descriptor[31] && held;
wire choose_relief=REMOTE_RELIEF && relief_enable && relief_available && (meta_cadence>=6 || boot_asset) && fifo_used>=512;
wire choose_av=!(REMOTE_RELIEF && relief_enable) && EXTENDED_AV && meta_cadence==8 && av_available && fifo_used>=512;
function [31:0] crc_bit;
 input [31:0] c;input b;
 begin crc_bit={c[30:0],1'b0}^((c[31]^b) ? 32'h04c11db7:32'd0);end
endfunction
wire [31:0] received_word={rx_shift[30:0],miso_sync};
wire valid_status=received_word[31:24]==8'hb6 && (received_word[14:11]==0 || (PAGE_CUE && received_word[11])) && received_word[10:8]<=5;
assign typed_pop=TYPED_PAGE && !change_audio && page_inflight && state==TRANSFER && divider==HALF_DIV-1 && !spi_sclk && bit_index==31 && word_index==0 && valid_status && received_word[11] && received_word[14:12]==page_seq;
always @(posedge clk or posedge rst)begin
 if(rst)begin hmi_transfer<=0;hmi_snapshot<=0;hmi_begin<=0;hmi_word_valid<=0;hmi_commit<=0;hmi_word_index<=0;hmi_word<=0;relief_transfer<=0;relief_query_hold<=0;relief_begin<=0;relief_word_valid<=0;relief_commit<=0;relief_finish<=0;relief_sent<=0;relief_sent_descriptor<=0;relief_word<=0;relief_word_index<=0;state<=IDLE;spi_cs<=1;spi_sclk<=0;spi_mosi<=0;divider<=0;idle_wait<=0;
  tx_shift<=0;rx_shift<=0;bit_index<=0;word_index<=0;payload_words<=0;
  finishing<=0;header_magic<=0;header_match<=0;av_transfer<=0;meta_cadence<=0;rx_av_crc<=32'hffffffff;av_begin<=0;av_word_valid<=0;av_finish<=0;av_commit<=0;av_word<=0;av_word_index<=0;
  page_inflight<=0;typed_control_due<=1;typed_control_packet<=0;packet_style<=0;page_ack<=0;catalog_complete<=0;sent_bg<=1;sent_volume<=5;sent_cue<=0;header_seen<=0;pcm_seen<=0;nonzero_seen<=0;track_count<=0;track_index<=0;desired_epoch<=0;packet_errors<=0;fifo_write<=0;fifo_input<=0;end
 else if(change_audio)begin
  hmi_begin<=0;hmi_word_valid<=0;hmi_commit<=0;hmi_transfer<=0;relief_finish<=relief_transfer;relief_commit<=0;relief_begin<=0;relief_word_valid<=0;relief_sent<=0;relief_transfer<=0;sent_bg<=bg_enable;sent_volume<=volume;sent_cue<=cue_event;
  if(change_track)track_index<=track_index==track_count-1 ? 0:track_index+1'b1;desired_epoch<=desired_epoch+1'b1;
  typed_control_due<=1;typed_control_packet<=0;state<=IDLE;spi_cs<=1;spi_sclk<=0;spi_mosi<=0;idle_wait<=CLK_HZ/1000;
  finishing<=0;fifo_write<=0;pcm_seen<=0;nonzero_seen<=0;av_begin<=0;av_word_valid<=0;av_commit<=0;av_finish<=1;av_transfer<=0;meta_cadence<=0;
 end else begin
  hmi_begin<=0;hmi_word_valid<=0;hmi_commit<=0;relief_begin<=0;relief_word_valid<=0;relief_commit<=0;relief_finish<=0;relief_sent<=0;fifo_write<=0;av_begin<=0;av_word_valid<=0;av_commit<=0;av_finish<=0;
  case(state)
   IDLE:begin
    if(idle_wait!=0)idle_wait<=idle_wait-1'b1;
    else if(send_page || fifo_used<=(1<<(FIFO_AW-1)) || choose_av || choose_relief)begin
     spi_cs<=0;spi_sclk<=0;spi_mosi<=1;divider<=0;
     hmi_transfer<=REMOTE_HMI && !send_page && !choose_relief && !choose_av;
     hmi_begin<=REMOTE_HMI && !send_page && !choose_relief && !choose_av;
     if(REMOTE_HMI)hmi_snapshot<={hmi_status[52:32],hmi_ack_token,hmi_ack_valid,hmi_reset_request,1'b0,hmi_status[31:0]};
     typed_control_packet<=TYPED_PAGE && send_page;
     if(TYPED_PAGE && send_page)begin
      page_inflight<=1;packet_style<=typed_head;
     end
     relief_transfer<=choose_relief && !send_page;relief_begin<=choose_relief && !send_page;
     if(choose_relief && !send_page)relief_query_hold<=relief_descriptor;
     else if(REMOTE_HMI)relief_query_hold<=hmi_session;
     av_transfer<=choose_av && !send_page;av_begin<=choose_av && !send_page;rx_av_crc<=32'hffffffff;
     if(choose_av && !send_page)meta_cadence<=0;
     tx_shift<={(send_page ? 8'ha8:choose_relief ? 8'ha9:choose_av ? 8'ha7:REMOTE_HMI ? 8'haa:8'ha6),desired_epoch,sent_bg,sent_volume,track_index,sent_cue,(PAGE_CUE ? (TYPED_PAGE && send_page ? outgoing_seq:page_seq):3'd0),repair_enable};rx_shift<=0;
     bit_index<=0;word_index<=0;payload_words<=0;finishing<=0;header_magic<=0;header_match<=0;state<=TRANSFER;
    end
   end
   TRANSFER:if(REMOTE_RESULT && relief_transfer && relief_query_hold[31] && word_index>=3 && word_index<=130 &&
    bit_index==0 && !spi_sclk && divider==HALF_DIV-1 && !relief_sink_ready)begin
    divider<=divider;
   end else if(divider==HALF_DIV-1)begin
    divider<=0;
    if(!spi_sclk)begin
     spi_sclk<=1;rx_shift<=received_word;
     if((REMOTE_HMI && hmi_transfer && word_index>=2 && word_index<6) || (av_transfer && word_index>=2 && word_index<292) || (REMOTE_RELIEF && relief_transfer && word_index>=2 && word_index<387))rx_av_crc<=crc_bit(rx_av_crc,miso_sync);
     
     if(bit_index==31)begin
      bit_index<=0;word_index<=word_index+1'b1;
      if(word_index==0)begin
       if(typed_pop)page_inflight<=0;
       if(PAGE_CUE && received_word[31:24]==8'hb6 && received_word[11] && received_word[10:8]<=5)page_ack<=received_word[14:12];
       header_magic<=valid_status;
       header_match<=received_word[23:16]==desired_epoch && received_word[7:0]=={5'd0,track_index};
       if(valid_status)begin catalog_complete<=received_word[15];track_count<=received_word[10:8];header_seen<=1;end
      end else if(word_index==1)begin
       if(REMOTE_RELIEF && relief_transfer && received_word==386)payload_words<=386;
       else if(av_transfer && received_word==291)payload_words<=291;
       else if(REMOTE_HMI && hmi_transfer && (received_word==133 || received_word==5))payload_words<=received_word[8:0];
       else if(!av_transfer && !relief_transfer && !hmi_transfer && received_word==128)payload_words<=128;
       else begin finishing<=1;
        if(received_word!=0 && packet_errors!=16'hffff)packet_errors<=packet_errors+1'b1;
       end
      end else if(word_index>=2 && word_index<2+payload_words)begin
       if(REMOTE_HMI && hmi_transfer && word_index<=6)begin
        if(word_index<6 && header_magic)begin hmi_word_valid<=1;hmi_word_index<=word_index-9'd2;hmi_word<=received_word;end
        if(word_index==6)begin
         hmi_commit<=header_magic && received_word==~rx_av_crc;
         if(received_word!=~rx_av_crc && packet_errors!=16'hffff)packet_errors<=packet_errors+1'b1;
        end
       end else if(REMOTE_RELIEF && relief_transfer)begin
        if(word_index<387 && header_magic && header_match)begin relief_word_valid<=1;relief_word_index<=word_index-9'd2;relief_word<=received_word;end
        if(word_index==387)begin relief_finish<=1;relief_commit<=header_magic && header_match && received_word==~rx_av_crc;
         if(received_word!=~rx_av_crc && packet_errors!=16'hffff)packet_errors<=packet_errors+1'b1;
        end
       end else if(av_transfer)begin
        if(word_index<292 && header_magic && header_match)begin av_word_valid<=1;av_word_index<=word_index-9'd2;av_word<=received_word;end
        if(word_index==292)begin
         av_finish<=1;av_commit<=header_magic && header_match && received_word==~rx_av_crc;
         if(received_word!=~rx_av_crc && packet_errors!=16'hffff)packet_errors<=packet_errors+1'b1;
        end
       end else if(header_magic && header_match)begin fifo_input<=received_word;fifo_write<=1;pcm_seen<=1;if(received_word!=0)nonzero_seen<=1;end
       if(word_index==1+payload_words)begin finishing<=1;
        if(relief_transfer)meta_cadence<=0;
        else if(!av_transfer && meta_cadence<8)meta_cadence<=meta_cadence+1'b1;
       end
      end
     end else bit_index<=bit_index+1'b1;
    end else begin
     spi_sclk<=0;
     if(REMOTE_HMI && hmi_transfer && word_index>=1 && word_index<=5 && bit_index==0)begin
      case(word_index)
       1:begin tx_shift<=hmi_snapshot[31:0];spi_mosi<=hmi_snapshot[31];end
       2:begin tx_shift<=hmi_snapshot[63:32];spi_mosi<=hmi_snapshot[63];end
       3:begin tx_shift<=relief_query_hold;spi_mosi<=relief_query_hold[31];end
       4:begin tx_shift<=~hmi_snapshot[31:0];spi_mosi<=~hmi_snapshot[31];end
       5:begin tx_shift<=~hmi_snapshot[63:32];spi_mosi<=~hmi_snapshot[63];end
      endcase
     end else if(REMOTE_RELIEF && relief_transfer && word_index==1 && bit_index==0)begin tx_shift<=relief_query_hold;spi_mosi<=relief_query_hold[31];end
     else if(TYPED_PAGE && typed_control_packet && word_index==1 && bit_index==0)begin tx_shift<=page_word;spi_mosi<=page_word[31];end
     else begin spi_mosi<=tx_shift[30];tx_shift<={tx_shift[30:0],1'b0};end
     if(finishing)begin
      if(TYPED_PAGE)typed_control_due<=!typed_control_packet;
      spi_cs<=1;spi_mosi<=0;
      if(av_transfer && payload_words!=291)av_finish<=1;
      if(REMOTE_RELIEF && relief_transfer)begin relief_sent<=1;relief_sent_descriptor<=relief_query_hold;if(payload_words!=386)relief_finish<=1;end
      state<=IDLE;idle_wait<=(payload_words==128 || (REMOTE_HMI && payload_words==133) || av_transfer || (relief_transfer && payload_words==386)) ? 0:CLK_HZ/1000;
     end
    end
   end else divider<=divider+1'b1;
   default:state<=IDLE;
  endcase
 end
end
endmodule
