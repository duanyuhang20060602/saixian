`timescale 1ns/1ps
module tb_resource_av_link;
reg ca=0,cb=0;always #6.666667 ca=~ca;always #5 cb=~cb;
reg rst=1,corrupt=1;wire sclk,cs,mosi,miso;
wire valid,begin_packet,word_valid,commit,finish,available,stream_reset;
wire [8:0] word_index,address;wire [31:0] word_data,play_position,metadata;
wire pcm_sent,snapshot;wire [7:0] requested_epoch,target;wire fft_valid,wave_valid;
wire damaged=miso ^ (corrupt && b.av_mode && b.word_index==4 && b.bit_index==8);
integer good=0,bad=0,frames=0;integer frame_clock=0;
wire tick=frame_clock==1237499;
always @(posedge ca)if(rst)frame_clock<=0;else frame_clock<=tick ? 0:frame_clock+1;
photo_audio_spi_a #(.CLK_HZ(75000000),.HALF_DIV(10),.FIFO_AW(11),.EXTENDED_AV(1)) a(
 .clk(ca),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(1'b0),.playback_hold(1'b0),
 .volume(4'd5),.cue_event(4'd0),.page_event(1'b0),.page_style(4'd0),
 .spi_miso(damaged),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.sample_valid(valid),
 .av_available(available),.av_begin(begin_packet),.av_word_valid(word_valid),.av_commit(commit),.av_finish(finish),
 .av_word_index(word_index),.av_word(word_data),.play_position(play_position),.stream_reset(stream_reset));
photo_audio_spi_b #(.EXTENDED_AV(1)) b(.clk(cb),.rst(rst),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.spi_miso(miso),
 .catalog_complete(1'b1),.active_epoch(requested_epoch),.active_track(3'd0),.track_count(3'd1),.switching(1'b0),
 .fifo_used(14'd8192),.processed_pcm({16'd10000,16'd8000}),.bg_enabled(1'b1),
 .request_epoch(requested_epoch),.av_data(metadata),.av_address(address),.pcm_sent(pcm_sent),.av_snapshot(snapshot),.page_ready(1'b1));
photo_av_metadata_b #(.EDGE_METADATA(1)) analysis(.clk(cb),.rst(rst),.pcm_sent(pcm_sent),.snapshot(snapshot),
 .pcm({16'd10000,16'd8000}),.address(address),.data(metadata));
photo_av_metadata_a #(.EDGE_METADATA(1)) cache(.clk(ca),.rst(rst || stream_reset),.frame_tick(tick),.play_position(play_position),
 .begin_packet(begin_packet),.word_valid(word_valid),.commit_packet(commit),.finish_packet(finish),
 .word_index(word_index),.word_data(word_data),.available(available),.read_band(5'd0),.read_index(8'd0),
 .fft_valid(fft_valid),.wave_valid(wave_valid),.edge_target(target));
always @(negedge ca)if(!rst)begin
 if(finish && a.av_transfer)begin
  if(commit)good=good+1;
  else begin bad=bad+1;corrupt=0;end
 end
 if(tick)frames=frames+1;
 if(cache.display_present && $signed(play_position-cache.position[cache.display_bank])<0)
  $fatal(1,"audio metadata became visible before its PCM playback position");
 if(bad>0 && good==0 && target!=0)$fatal(1,"corrupt SPI metadata reached the renderer");
end
initial begin
 repeat(8)@(negedge ca);rst=0;
 wait(bad==1 && good>=2 && target==255);
 if(a.packet_errors!=1)$fatal(1,"unexpected SPI CRC/error count %0d",a.packet_errors);
 if(play_position==0 || analysis.sent_position<=play_position)$fatal(1,"look-ahead not exercised");
 @(negedge ca);rst=1;repeat(3)@(negedge ca);
 if(target!=0 || fft_valid || wave_valid)$fatal(1,"old audio epoch survived reset");
 $display("PASS real asynchronous A/B SPI: AV2 metadata, one injected CRC error, %0d good packets, %0d frame boundaries, no future-audio publication, reset",good,frames);
 $finish;
end
initial begin
 wait(!rst);repeat(250000)@(negedge ca);
 if(!a.header_seen || !a.pcm_seen)$fatal(1,"SPI setup failed header=%0d PCM=%0d epoch=%0d Bepoch=%0d",a.header_seen,a.pcm_seen,a.desired_epoch,requested_epoch);
end
initial begin #300000000;$fatal(1,"AV SPI timeout good=%0d bad=%0d target=%0d play=%0d sent=%0d",good,bad,target,play_position,analysis.sent_position);end
endmodule
