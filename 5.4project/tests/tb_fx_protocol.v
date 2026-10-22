`timescale 1ns/1ps
module tb_fx_protocol;
reg ca=0,cb=0;always #6.666667 ca=~ca;always #5 cb=~cb;
reg rst=1,page=0,ready=0,corrupt=1;reg [3:0] style=0;
wire sclk,cs,mosi,miso,pv;wire [3:0] received_style;
wire bad_mosi=corrupt && b.control_only && b.word_index==1 ? 1'b0:mosi;
integer accepted=0,controls=0,i;
photo_audio_spi_a #(.CLK_HZ(48000),.FIFO_AW(11),.PAGE_CUE(1),.TYPED_PAGE(1)) a(
 .clk(ca),.rst(rst),.next_track(1'b0),.bg_enable(1'b1),.repair_enable(1'b0),.playback_hold(1'b0),.volume(4'd5),.cue_event(4'd0),.spi_miso(miso),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(mosi),.av_available(1'b0),.page_event(page),.page_style(style));
photo_audio_spi_b #(.PAGE_CUE(1),.TYPED_PAGE(1)) b(
 .clk(cb),.rst(rst),.spi_sclk(sclk),.spi_cs(cs),.spi_mosi(bad_mosi),.spi_miso(miso),.catalog_complete(1'b0),.active_epoch(8'd0),.active_track(3'd0),.track_count(3'd1),.switching(1'b0),.fifo_used(14'd0),.processed_pcm(32'd0),.bg_enabled(1'b1),.av_data(32'd0),.page_valid(pv),.page_style(received_style),.page_ready(ready));
always @(negedge cb)if(!rst)begin
 if(b.request_valid && b.control_only)controls=controls+1;
 if(pv)begin
  if(received_style!==accepted%11)$fatal(1,"style mismatch at %0d",accepted);
  accepted=accepted+1;
 end
 if(b.fifo_read || b.sample_prepare)$fatal(1,"control-only packet consumed PCM");
end
task event_send;input [3:0] s;begin @(negedge ca);style=s;page=1;@(negedge ca);page=0;end endtask
initial begin
 repeat(5)@(negedge cb);rst=0;event_send(0);
 wait(controls>=3);if(accepted!=0 || b.seen_page_seq!=0)$fatal(1,"bad metadata accepted");
 corrupt=0;wait(controls>=6);if(accepted!=0 || !a.typed_valid)$fatal(1,"full receiver lost event");
 force b.status_word=32'hb6000900;ready=1;
 wait(accepted==1);wait(controls>=10);
 if(accepted!=1 || !a.typed_valid)$fatal(1,"ACK loss caused duplicate/loss");
 release b.status_word;wait(!a.typed_valid && !a.page_inflight);
 for(i=1;i<20;i=i+1)begin
  event_send(i%11);wait(a.typed_valid);wait(!a.typed_valid && !a.page_inflight);
 end
 repeat(100)@(negedge cb);
 if(accepted!=20 || a.outgoing_pages.overflow || a.desired_epoch!=0 || a.packet_errors!=0)$fatal(1,"protocol lost events or reset stream");
 $display("PASS typed SPI: corrupt metadata rejection, queue-full backpressure, ACK loss/retries deduplicated, 20 ordered styles, sequence wrap, no PCM reads/stream reset");$finish;
end
initial begin #5000000;$fatal(1,"typed protocol timeout accepted=%0d controls=%0d seq=%0d seen=%0d",accepted,controls,a.page_seq,b.seen_page_seq);end
endmodule
