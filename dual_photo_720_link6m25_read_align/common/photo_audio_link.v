`timescale 1ns/1ps
// Both ends run from their system clocks. SPI pins are oversampled; no
// fabric-generated clock clocks internal logic. Mode 0, MSB first.
module photo_audio_fifo #(parameter DEPTH=8192,AW=13)(
 input clk,rst,input write_en,input [31:0] write_data,input read_en,
 output reg [31:0] data,output empty,full,output reg [AW:0] used
);
reg [31:0] memory[0:DEPTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [AW-1:0] wp,rp;
wire push=write_en && !full,pop=read_en && !empty;
assign empty=used==0;assign full=used==DEPTH;
always @(posedge clk)begin
 if(push)memory[wp]<=write_data;
 if(pop)data<=memory[rp];
end
always @(posedge clk or posedge rst)begin
 if(rst)begin wp<=0;rp<=0;used<=0;end
 else begin
  if(push)wp<=wp+1'b1;if(pop)rp<=rp+1'b1;
  case({push,pop})2'b10:used<=used+1'b1;2'b01:used<=used-1'b1;default:;endcase
 end
end
endmodule

module photo_audio_spi_b(
 input clk,rst,input spi_sclk,spi_cs,spi_mosi,output reg spi_miso,output packet_active,
 input [7:0] active_epoch,input [2:0] active_track,track_count,input switching,
 input [13:0] fifo_used,input [31:0] processed_pcm,input bg_enabled,output reg sample_prepare,output reg fifo_read,
 output reg request_valid,output reg [7:0] request_epoch,output reg [2:0] request_track,
 output reg request_bg,output reg [3:0] request_volume,request_cue
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
wire [31:0] status_word={8'hb6,active_epoch,5'd0,track_count,5'd0,active_track};
always @(posedge clk or posedge rst)begin
 if(rst)begin spi_miso<=0;tx_shift<=0;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
  packet_epoch<=0;payload_words<=0;fifo_read<=0;sample_prepare<=0;request_bg<=1;request_volume<=5;request_cue<=0;request_valid<=0;request_epoch<=0;request_track<=0;end
 else begin
  fifo_read<=0;sample_prepare<=0;request_valid<=0;
  if(cs_previous && !cs_sync)begin
   tx_shift<=status_word;spi_miso<=1;rx_shift<=0;bit_index<=0;word_index<=0;word_complete<=0;
   packet_epoch<=active_epoch;payload_words<=0;
  end else if(cs_sync)begin spi_miso<=0;word_complete<=0;end
  else begin
   if(rise)begin
    rx_shift<=received_word;
    
    if(bit_index==29 && payload_words==128 && word_index>=1 && word_index<129)begin fifo_read<=bg_enabled;sample_prepare<=1;end
    if(bit_index==31)begin
     bit_index<=0;word_index<=word_index+1'b1;word_complete<=1;
     if(word_index==0 && received_word[31:24]==8'ha6)begin
      request_valid<=1;request_epoch<=received_word[23:16];request_track<=received_word[10:8];request_bg<=received_word[15];request_volume<=received_word[14:11];request_cue<=received_word[7:4];
     end
    end else bit_index<=bit_index+1'b1;
   end
   if(fall)begin
    if(word_complete)begin
     word_complete<=0;
     if(word_index==1)begin
      payload_words<=can_send ? 9'd128:9'd0;
      tx_shift<=can_send ? 32'd128:32'd0;spi_miso<=0;
     end else if(word_index>=2 && word_index<2+payload_words)begin tx_shift<=processed_pcm;spi_miso<=processed_pcm[31];end
     else begin tx_shift<=0;spi_miso<=0;end
    end else begin spi_miso<=tx_shift[30];tx_shift<={tx_shift[30:0],1'b0};end
   end
  end
 end
end
endmodule

module photo_audio_spi_a #(parameter CLK_HZ=75000000,HALF_DIV=10)(
 input clk,rst,next_track,bg_enable,input [3:0] volume,cue_event,input spi_miso,output reg spi_sclk,spi_cs,spi_mosi,
 output reg [2:0] track_count,track_index,output reg [7:0] desired_epoch,
 output reg sample_valid,output reg [23:0] audio_left,audio_right,
 output reg [15:0] packet_errors,underflows,
 output [3:0] diagnostic_stage,buffer_level,output reg header_seen,pcm_seen,nonzero_seen
);
reg spi_miso_meta,miso_sync;
always @(posedge clk or posedge rst)begin
 if(rst)begin spi_miso_meta<=0;miso_sync<=0;end
 else begin spi_miso_meta<=spi_miso;miso_sync<=spi_miso_meta;end
end
wire change_track=next_track && track_count>1;
reg sent_bg;reg [3:0] sent_volume,sent_cue;
wire change_control=volume!=sent_volume || bg_enable!=sent_bg || cue_event!=0;
wire change_audio=change_track || change_control;
wire fifo_rst=rst || change_audio;
wire [31:0] fifo_data;wire fifo_empty,fifo_full;wire [13:0] fifo_used;
reg fifo_write;reg [31:0] fifo_input;
reg sample_ready,read_pending;reg [31:0] sample_word;
wire fifo_read=!sample_ready && !read_pending && !fifo_empty;
photo_audio_fifo fifo(.clk(clk),.rst(fifo_rst),.write_en(fifo_write && !change_audio),.write_data(fifo_input),
 .read_en(fifo_read && !change_audio),.data(fifo_data),.empty(fifo_empty),.full(fifo_full),.used(fifo_used));
reg [26:0] sample_phase;reg playing;
wire sample_tick=sample_phase>=CLK_HZ-48000;
assign buffer_level=fifo_used[13] ? 4'd8:{1'b0,fifo_used[12:10]};
assign diagnostic_stage=!header_seen ? 4'd1:track_count==0 ? 4'd2:!pcm_seen ? 4'd3:
 !playing ? 4'd4:underflows!=0 ? 4'd6:4'd5;
always @(posedge clk or posedge rst)begin
 if(rst)begin sample_phase<=0;sample_valid<=0;audio_left<=0;audio_right<=0;
  sample_ready<=0;read_pending<=0;sample_word<=0;playing<=0;underflows<=0;end
 else begin
  sample_valid<=sample_tick;
  sample_phase<=sample_tick ? sample_phase-(CLK_HZ-48000):sample_phase+27'd48000;
  if(change_audio)begin sample_ready<=0;read_pending<=0;playing<=0;audio_left<=0;audio_right<=0;underflows<=0;end
  else begin
   read_pending<=fifo_read;
   if(read_pending)begin sample_word<=fifo_data;sample_ready<=1;end
   if(!playing && fifo_used>=512)playing<=1;
   if(sample_tick)begin
    if(playing && sample_ready)begin audio_left<={sample_word[15:0],8'd0};audio_right<={sample_word[31:16],8'd0};sample_ready<=0;end
    else begin audio_left<=0;audio_right<=0;if(playing && underflows!=16'hffff)underflows<=underflows+1'b1;end
   end
  end
 end
end
localparam IDLE=0,TRANSFER=1;
reg [1:0] state;reg [3:0] divider;reg [16:0] idle_wait;
reg [31:0] tx_shift,rx_shift;reg [5:0] bit_index;reg [8:0] word_index,payload_words;
reg finishing,header_magic,header_match;
wire [31:0] received_word={rx_shift[30:0],miso_sync};
always @(posedge clk or posedge rst)begin
 if(rst)begin state<=IDLE;spi_cs<=1;spi_sclk<=0;spi_mosi<=0;divider<=0;idle_wait<=0;
  tx_shift<=0;rx_shift<=0;bit_index<=0;word_index<=0;payload_words<=0;
  finishing<=0;header_magic<=0;header_match<=0;
  sent_bg<=1;sent_volume<=5;sent_cue<=0;header_seen<=0;pcm_seen<=0;nonzero_seen<=0;track_count<=0;track_index<=0;desired_epoch<=0;packet_errors<=0;fifo_write<=0;fifo_input<=0;end
 else if(change_audio)begin
  sent_bg<=bg_enable;sent_volume<=volume;sent_cue<=cue_event;
  if(change_track)track_index<=track_index==track_count-1 ? 0:track_index+1'b1;desired_epoch<=desired_epoch+1'b1;
  state<=IDLE;spi_cs<=1;spi_sclk<=0;spi_mosi<=0;idle_wait<=CLK_HZ/1000;
  finishing<=0;fifo_write<=0;pcm_seen<=0;nonzero_seen<=0;
 end else begin
  fifo_write<=0;
  case(state)
   IDLE:begin
    if(idle_wait!=0)idle_wait<=idle_wait-1'b1;
    else if(fifo_used<=4096)begin
     spi_cs<=0;spi_sclk<=0;spi_mosi<=1;divider<=0;
     tx_shift<={8'ha6,desired_epoch,sent_bg,sent_volume,track_index,sent_cue,4'd0};rx_shift<=0;
     bit_index<=0;word_index<=0;payload_words<=0;finishing<=0;header_magic<=0;header_match<=0;state<=TRANSFER;
    end
   end
   TRANSFER:if(divider==HALF_DIV-1)begin
    divider<=0;
    if(!spi_sclk)begin
     spi_sclk<=1;rx_shift<=received_word;
     
     if(bit_index==31)begin
      bit_index<=0;word_index<=word_index+1'b1;
      if(word_index==0)begin
       header_magic<=received_word[31:24]==8'hb6 && received_word[15:8]<=5;
       header_match<=received_word[23:16]==desired_epoch && received_word[7:0]=={5'd0,track_index};
       if(received_word[31:24]==8'hb6 && received_word[15:8]<=5)begin track_count<=received_word[10:8];header_seen<=1;end
      end else if(word_index==1)begin
       if(received_word==128)payload_words<=128;
       else begin finishing<=1;
        if(received_word!=0 && packet_errors!=16'hffff)packet_errors<=packet_errors+1'b1;
       end
      end else if(word_index>=2 && word_index<2+payload_words)begin
       if(header_magic && header_match)begin fifo_input<=received_word;fifo_write<=1;pcm_seen<=1;if(received_word!=0)nonzero_seen<=1;end
       if(word_index==1+payload_words)finishing<=1;
      end
     end else bit_index<=bit_index+1'b1;
    end else begin
     spi_sclk<=0;spi_mosi<=tx_shift[30];tx_shift<={tx_shift[30:0],1'b0};
     if(finishing)begin
      spi_cs<=1;spi_mosi<=0;
      state<=IDLE;idle_wait<=payload_words==128 ? 0:CLK_HZ/1000;
     end
    end
   end else divider<=divider+1'b1;
   default:state<=IDLE;
  endcase
 end
end
endmodule
