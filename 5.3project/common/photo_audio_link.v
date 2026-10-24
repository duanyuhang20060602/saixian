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

module photo_audio_spi_b #(parameter CATALOG_STATUS=0,EXTENDED_AV=0,PAGE_CUE=0,TYPED_PAGE=0)(
 input clk,rst,input spi_sclk,spi_cs,spi_mosi,output reg spi_miso,output packet_active,
 input catalog_complete,input [7:0] active_epoch,input [2:0] active_track,track_count,input switching,
 input [13:0] fifo_used,input [31:0] processed_pcm,input bg_enabled,output reg sample_prepare,output reg fifo_read,
 output reg request_valid,output reg [7:0] request_epoch,output reg [2:0] request_track,
 output reg request_bg,request_repair,output reg [3:0] request_volume,request_cue,
 output reg pcm_sent,av_snapshot,output [8:0] av_address,input [31:0] av_data,output reg [2:0] page_cue_count,output reg page_valid,output reg [3:0] page_style,input page_ready
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
reg av_mode,control_only;reg [2:0] seen_page_seq,control_page_seq;
wire typed_word_ok=received_word[31:24]==8'hd8 && received_word[23:21]==control_page_seq && received_word[20:17]<=10 &&
 received_word[16:9]==0 && received_word[8:6]==~received_word[23:21] && received_word[5:2]==~received_word[20:17] && received_word[1:0]==0;
reg [31:0] av_prepared,av_crc;
assign av_address=word_index-9'd1;
function [31:0] av_crc_bit;
 input [31:0] c;input b;
 begin av_crc_bit={c[30:0],1'b0}^((c[31]^b) ? 32'h04c11db7:32'd0);end
endfunction
wire [31:0] status_word={8'hb6,active_epoch,(CATALOG_STATUS ? catalog_complete:1'b0),(PAGE_CUE ? {seen_page_seq,1'b1}:4'd0),track_count,5'd0,active_track};
always @(posedge clk or posedge rst)begin
 if(rst)begin spi_miso<=0;tx_shift<=0;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
  seen_page_seq<=0;control_page_seq<=0;page_valid<=0;page_style<=0;page_cue_count<=0;control_only<=0;packet_epoch<=0;payload_words<=0;av_mode<=0;av_prepared<=0;av_crc<=32'hffffffff;pcm_sent<=0;av_snapshot<=0;fifo_read<=0;sample_prepare<=0;request_bg<=1;request_repair<=0;request_volume<=5;request_cue<=0;request_valid<=0;request_epoch<=0;request_track<=0;end
 else begin
  page_valid<=0;page_cue_count<=0;fifo_read<=0;sample_prepare<=0;request_valid<=0;pcm_sent<=0;av_snapshot<=0;
  if(cs_previous && !cs_sync)begin
   tx_shift<=status_word;spi_miso<=1;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
   packet_epoch<=active_epoch;payload_words<=0;av_mode<=0;control_only<=0;av_crc<=32'hffffffff;
  end else if(cs_sync)begin spi_miso<=0;word_complete<=0;end
  else begin
   if(rise)begin
    rx_shift<=received_word;
    if(EXTENDED_AV && av_mode && word_index>=2 && word_index<292)av_crc<=av_crc_bit(av_crc,spi_miso);
    if(EXTENDED_AV && av_mode && bit_index==24)av_prepared<=av_data;
        if(!av_mode && bit_index==16 && payload_words==128 && word_index>=1 && word_index<129)begin fifo_read<=bg_enabled;sample_prepare<=1;end
    if(bit_index==31)begin
     bit_index<=0;word_index<=word_index+1'b1;word_complete<=1;
     if(EXTENDED_AV && word_index==0 && received_word[31:24]==8'ha7)begin av_mode<=1;av_snapshot<=1;end
     if(word_index==0 && (received_word[31:24]==8'ha6 || (PAGE_CUE && received_word[31:24]==8'ha8)))begin
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
     if(word_index==1)begin
      payload_words<=av_mode ? 9'd291:control_only ? 9'd0:can_send ? 9'd128:9'd0;
      tx_shift<=av_mode ? 32'd291:control_only ? 32'd0:can_send ? 32'd128:32'd0;spi_miso<=0;
     end else if(av_mode && word_index>=2 && word_index<293)begin
      tx_shift<=word_index==292 ? ~av_crc:av_prepared;
      spi_miso<=word_index==292 ? ~av_crc[31]:av_prepared[31];
     end else if(!av_mode && word_index>=2 && word_index<2+payload_words)begin tx_shift<=processed_pcm;spi_miso<=processed_pcm[31];pcm_sent<=1;end
     else begin tx_shift<=0;spi_miso<=0;end
    end else begin spi_miso<=tx_shift[30];tx_shift<={tx_shift[30:0],1'b0};end
   end
  end
 end
end
endmodule

module photo_audio_spi_a #(parameter CLK_HZ=75000000,HALF_DIV=10,STARTUP_SYNC=0,FIFO_AW=13,EXTENDED_AV=0,FIFO_RAM32_HEAD=0,PAGE_CUE=0,TYPED_PAGE=0)(
 input clk,rst,next_track,bg_enable,repair_enable,playback_hold,input [3:0] volume,cue_event,input spi_miso,output reg spi_sclk,spi_cs,spi_mosi,
 output buffer_ready,output reg catalog_complete,output reg [2:0] track_count,track_index,output reg [7:0] desired_epoch,
 output reg sample_valid,output reg [23:0] audio_left,audio_right,
 output reg [15:0] packet_errors,underflows,
 output [3:0] diagnostic_stage,buffer_level,output reg header_seen,pcm_seen,nonzero_seen,
 input av_available,output reg av_begin,av_word_valid,av_commit,av_finish,
 output reg [8:0] av_word_index,output reg [31:0] av_word,
 output reg [31:0] play_position,output stream_reset,input page_event,input [3:0] page_style
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
reg av_transfer;reg [3:0] meta_cadence;reg [31:0] rx_av_crc;
wire choose_av=EXTENDED_AV && meta_cadence==8 && av_available && fifo_used>=512;
function [31:0] crc_bit;
 input [31:0] c;input b;
 begin crc_bit={c[30:0],1'b0}^((c[31]^b) ? 32'h04c11db7:32'd0);end
endfunction
wire [31:0] received_word={rx_shift[30:0],miso_sync};
wire valid_status=received_word[31:24]==8'hb6 && (received_word[14:11]==0 || (PAGE_CUE && received_word[11])) && received_word[10:8]<=5;
assign typed_pop=TYPED_PAGE && !change_audio && page_inflight && state==TRANSFER && divider==HALF_DIV-1 && !spi_sclk && bit_index==31 && word_index==0 && valid_status && received_word[11] && received_word[14:12]==page_seq;
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=IDLE;spi_cs<=1;spi_sclk<=0;spi_mosi<=0;divider<=0;idle_wait<=0;
  tx_shift<=0;rx_shift<=0;bit_index<=0;word_index<=0;payload_words<=0;
  finishing<=0;header_magic<=0;header_match<=0;av_transfer<=0;meta_cadence<=0;rx_av_crc<=32'hffffffff;av_begin<=0;av_word_valid<=0;av_finish<=0;av_commit<=0;av_word<=0;av_word_index<=0;
  page_inflight<=0;typed_control_due<=1;typed_control_packet<=0;packet_style<=0;page_ack<=0;catalog_complete<=0;sent_bg<=1;sent_volume<=5;sent_cue<=0;header_seen<=0;pcm_seen<=0;nonzero_seen<=0;track_count<=0;track_index<=0;desired_epoch<=0;packet_errors<=0;fifo_write<=0;fifo_input<=0;end
 else if(change_audio)begin
  sent_bg<=bg_enable;sent_volume<=volume;sent_cue<=cue_event;
  if(change_track)track_index<=track_index==track_count-1 ? 0:track_index+1'b1;desired_epoch<=desired_epoch+1'b1;
  typed_control_due<=1;typed_control_packet<=0;state<=IDLE;spi_cs<=1;spi_sclk<=0;spi_mosi<=0;idle_wait<=CLK_HZ/1000;
  finishing<=0;fifo_write<=0;pcm_seen<=0;nonzero_seen<=0;av_begin<=0;av_word_valid<=0;av_commit<=0;av_finish<=1;av_transfer<=0;meta_cadence<=0;
 end else begin
  fifo_write<=0;av_begin<=0;av_word_valid<=0;av_commit<=0;av_finish<=0;
  case(state)
   IDLE:begin
    if(idle_wait!=0)idle_wait<=idle_wait-1'b1;
    else if(send_page || fifo_used<=(1<<(FIFO_AW-1)) || choose_av)begin
     spi_cs<=0;spi_sclk<=0;spi_mosi<=1;divider<=0;
     typed_control_packet<=TYPED_PAGE && send_page;
     if(TYPED_PAGE && send_page)begin
      page_inflight<=1;packet_style<=typed_head;
     end
     av_transfer<=choose_av && !send_page;av_begin<=choose_av && !send_page;rx_av_crc<=32'hffffffff;
     if(choose_av && !send_page)meta_cadence<=0;
     tx_shift<={(send_page ? 8'ha8:choose_av ? 8'ha7:8'ha6),desired_epoch,sent_bg,sent_volume,track_index,sent_cue,(PAGE_CUE ? (TYPED_PAGE && send_page ? outgoing_seq:page_seq):3'd0),repair_enable};rx_shift<=0;
     bit_index<=0;word_index<=0;payload_words<=0;finishing<=0;header_magic<=0;header_match<=0;state<=TRANSFER;
    end
   end
   TRANSFER:if(divider==HALF_DIV-1)begin
    divider<=0;
    if(!spi_sclk)begin
     spi_sclk<=1;rx_shift<=received_word;
     if(av_transfer && word_index>=2 && word_index<292)rx_av_crc<=crc_bit(rx_av_crc,miso_sync);
     
     if(bit_index==31)begin
      bit_index<=0;word_index<=word_index+1'b1;
      if(word_index==0)begin
       if(typed_pop)page_inflight<=0;
       if(PAGE_CUE && received_word[31:24]==8'hb6 && received_word[11] && received_word[10:8]<=5)page_ack<=received_word[14:12];
       header_magic<=valid_status;
       header_match<=received_word[23:16]==desired_epoch && received_word[7:0]=={5'd0,track_index};
       if(valid_status)begin catalog_complete<=received_word[15];track_count<=received_word[10:8];header_seen<=1;end
      end else if(word_index==1)begin
       if(av_transfer && received_word==291)payload_words<=291;
       else if(!av_transfer && received_word==128)payload_words<=128;
       else begin finishing<=1;
        if(received_word!=0 && packet_errors!=16'hffff)packet_errors<=packet_errors+1'b1;
       end
      end else if(word_index>=2 && word_index<2+payload_words)begin
       if(av_transfer)begin
        if(word_index<292 && header_magic && header_match)begin av_word_valid<=1;av_word_index<=word_index-9'd2;av_word<=received_word;end
        if(word_index==292)begin
         av_finish<=1;av_commit<=header_magic && header_match && received_word==~rx_av_crc;
         if(received_word!=~rx_av_crc && packet_errors!=16'hffff)packet_errors<=packet_errors+1'b1;
        end
       end else if(header_magic && header_match)begin fifo_input<=received_word;fifo_write<=1;pcm_seen<=1;if(received_word!=0)nonzero_seen<=1;end
       if(word_index==1+payload_words)begin finishing<=1;
        if(!av_transfer && meta_cadence<8)meta_cadence<=meta_cadence+1'b1;
       end
      end
     end else bit_index<=bit_index+1'b1;
    end else begin
     spi_sclk<=0;
     if(TYPED_PAGE && typed_control_packet && word_index==1 && bit_index==0)begin tx_shift<=page_word;spi_mosi<=page_word[31];end
     else begin spi_mosi<=tx_shift[30];tx_shift<={tx_shift[30:0],1'b0};end
     if(finishing)begin
      if(TYPED_PAGE)typed_control_due<=!typed_control_packet;
      spi_cs<=1;spi_mosi<=0;
      if(av_transfer && payload_words!=291)av_finish<=1;
      state<=IDLE;idle_wait<=(payload_words==128 || av_transfer) ? 0:CLK_HZ/1000;
     end
    end
   end else divider<=divider+1'b1;
   default:state<=IDLE;
  endcase
 end
end
endmodule
