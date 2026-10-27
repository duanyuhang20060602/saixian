`timescale 1ns/1ps
module tb_hmi_remote_spi;
reg ca=0,cb=0;always #6.666667 ca=~ca;always #5 cb=~cb;
reg rst=1;reg [31:0] session=32'h12345678;
wire sclk,cs,mosi,miso;wire [31:0] hdr,hw;wire [95:0] payload;
wire hb,hv,hc,ack,reset_req,enabled,restart,back;wire [1:0] hi;wire [7:0] token,btoken;
reg [52:0] status={1'b0,3'd6,3'd5,3'd0,1'b0,3'd0,2'd1,4'd4,4'd4,4'd4,4'd8,1'b0,1'b0,2'd1,4'd6,7'd12,6'd34};
wire [52:0] remote_status;wire bv,br,done;wire [7:0] bd;wire uart;
wire prepare,read,pcm_sent,pv;wire [3:0] pstyle;reg switching=0,relief_enable=0,page_event=0;
reg [31:0] processed=0,raw=32'h01000100;
always @(posedge cb)if(rst)begin raw<=32'h01000100;processed<=0;end else if(prepare)begin processed<=raw;raw<=raw+32'h00010001;end
photo_audio_spi_b_offload #(.CATALOG_STATUS(1),.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1),.REMOTE_RELIEF(1),.REMOTE_HMI(1)) b(
 .clk(cb),.rst(rst),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.spi_miso(miso),.packet_active(),
 .catalog_complete(1'b1),.active_epoch(8'd0),.active_track(3'd0),.track_count(3'd1),.switching(switching),
 .fifo_used(14'd8192),.processed_pcm(processed),.bg_enabled(1'b1),.sample_prepare(prepare),.fifo_read(read),
 .request_valid(),.request_epoch(),.request_track(),.request_bg(),.request_repair(),.request_volume(),.request_cue(),
 .pcm_sent(pcm_sent),.av_snapshot(),.av_address(),.av_data(32'habcde123),.page_cue_count(),.page_valid(pv),.page_style(pstyle),.page_ready(1'b1),
 .relief_ready(1'b1),.relief_descriptor(32'h12340000),.relief_data(32'h56780000),.relief_address(),.relief_request(),.relief_query(),
 .hmi_session(session),.hmi_header(hdr),.hmi_payload(payload),.hmi_status(remote_status),.hmi_enabled(enabled),.hmi_ack_valid(back),.hmi_ack_token(btoken),.hmi_restart(restart));
wire hreset=rst || !enabled || restart;
saixian_hmi_status_tx #(.CLK_FREQ_HZ(100000000),.ENHANCEMENT_FEEDBACK(1),.BYTE_STREAM(1)) format(
 .clk(cb),.rst(hreset),.image_count(remote_status[51:49]),.audio_count(remote_status[48:46]),.error_code(remote_status[45:43]),
 .initializing(remote_status[42]),.page_id(remote_status[41:39]),.refresh_request(1'b0),.sharpness(remote_status[38:37]),
 .brightness(remote_status[36:33]),.contrast(remote_status[32:29]),.saturation(remote_status[28:25]),.volume(remote_status[24:21]),
 .invert(remote_status[20]),.vintage(remote_status[19]),.enhancement(remote_status[18:17]),.event_state(remote_status[16:13]),
 .minutes(remote_status[12:6]),.seconds(remote_status[5:0]),.uart_tx(),.command_sent_pulse(done),.byte_valid(bv),.byte_data(bd),.byte_ready(br));
photo_hmi_chunk_b #(.CHUNK_BYTES(8)) chunks(.clk(cb),.rst(hreset),.byte_valid(bv),.byte_data(bd),.byte_ready(br),.command_done(done),
 .ack_valid(back),.ack_token(btoken),.header(hdr),.payload(payload));
photo_hmi_relay_a #(.CHUNK_BYTES(8)) relay(.clk(ca),.rst(rst),.session(session),.packet_begin(hb),.word_valid(hv),.word_index(hi),.word_data(hw),.commit(hc),
 .ack_valid(ack),.ack_token(token),.reset_request(reset_req),.uart_tx(uart));
reg corrupt=0;wire faulty_miso=miso ^ (corrupt && a.hmi_transfer && a.word_index==4 && a.bit_index==8);
wire [15:0] errors,underflows;wire avcommit,rcommit,sample_valid;wire [23:0] left,right;
photo_audio_spi_a #(.STARTUP_SYNC(1),.FIFO_AW(11),.FIFO_RAM32_HEAD(2048),.EXTENDED_AV(1),.PAGE_CUE(1),.TYPED_PAGE(1),.REMOTE_RELIEF(1),.REMOTE_HMI(1)) a(
 .clk(ca),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(1'b0),.playback_hold(1'b0),.volume(4'd5),.cue_event(4'd0),
 .spi_miso(faulty_miso),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.buffer_ready(),.catalog_complete(),.track_count(),.track_index(),.desired_epoch(),
 .sample_valid(sample_valid),.audio_left(left),.audio_right(right),.packet_errors(errors),.underflows(underflows),.diagnostic_stage(),.buffer_level(),.header_seen(),.pcm_seen(),.nonzero_seen(),
 .av_available(1'b1),.av_begin(),.av_word_valid(),.av_commit(avcommit),.av_finish(),.av_word_index(),.av_word(),.play_position(),.stream_reset(),.page_event(page_event),.page_style(4'd7),
 .relief_enable(relief_enable),.relief_available(1'b1),.relief_descriptor(32'h98760000),.relief_begin(),.relief_word_valid(),.relief_commit(rcommit),.relief_finish(),.relief_sent(),.relief_sent_descriptor(),.relief_word(),.relief_word_index(),
 .hmi_status(status),.hmi_session(session),.hmi_ack_valid(ack),.hmi_reset_request(reset_req),.hmi_ack_token(token),.hmi_begin(hb),.hmi_word_valid(hv),.hmi_word_index(hi),.hmi_word(hw),.hmi_commit(hc));
reg [31:0] pcm_expected[0:16383];reg [7:0] text_expected[0:4095];integer wp=0,rp=0,wt=0,rt=0,flush=0,k;
integer avs=0,rels=0,pages=0,packets=0,hmionly=0,crc_good=0;reg [7:0] decoded;
always @(posedge cb)begin
 if(pcm_sent)begin pcm_expected[wp]=processed;wp=wp+1;end
 if(!hreset && bv && br)begin text_expected[wt]=bd;wt=wt+1;end
 if(pv)begin if(pstyle!=7)$fatal(1,"wrong page style");pages=pages+1;end
end
always @(posedge ca)begin
 if(a.fifo_write)begin
  if(rp>=wp || a.fifo_input!==pcm_expected[rp])$fatal(1,"PCM sequence %0d got %h expected %h",rp,a.fifo_input,pcm_expected[rp]);rp=rp+1;
 end
 if(avcommit)avs=avs+1;if(rcommit)rels=rels+1;if(hc)crc_good=crc_good+1;
 if(!rst && a.state==1 && a.word_index==2 && a.bit_index==0 && a.divider==0 && sclk)begin packets=packets+1;if(a.payload_words==5)hmionly=hmionly+1;end
end
always begin
 @(negedge uart);if(!rst)begin
  repeat(976)@(negedge ca);
  for(k=0;k<8;k=k+1)begin decoded[k]=uart;repeat(651)@(negedge ca);end
  if(!uart)$fatal(1,"stop bit");
  if(flush<3)begin if(decoded!=255)$fatal(1,"missing startup terminator");flush=flush+1;end
  else begin if(rt>=wt || decoded!==text_expected[rt])$fatal(1,"HMI byte %0d got %h expected %h",rt,decoded,text_expected[rt]);rt=rt+1;end
 end
end
initial begin
 repeat(50)@(negedge ca);rst=0;
 #12000000;corrupt=1;
 #4000000;corrupt=0;switching=1;
 #3000000;switching=0;
 #9000000;relief_enable=1;
 @(negedge ca);page_event=1;@(negedge ca);page_event=0;
 #18000000;
 if(remote_status!==status)$fatal(1,"status snapshot");
 if(errors==0 || underflows!=0 || rt<58 || avs==0 || rels==0 || pages!=1 || hmionly==0 || rp<1000 || crc_good<10)
  $fatal(1,"coverage err=%d under=%d text=%d av=%d rel=%d pages=%d hmi-only=%d pcm=%d good=%d",errors,underflows,rt,avs,rels,pages,hmionly,rp,crc_good);
 $display("PASS real A/B SPI: %0d PCM words exact, %0d UART bytes exact, CRC errors/retries=%0d AV=%0d relief=%0d pages=%0d HMI-only=%0d underflows=%0d",rp,rt,errors,avs,rels,pages,hmionly,underflows);$finish;
end
initial begin #60000000;$fatal(1,"timeout");end
endmodule
