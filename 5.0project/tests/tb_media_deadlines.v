`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,scanning=0,loading=0,progress=0,started=0;always #5 clk=~clk;
photo_sd_cache #(.CLK_HZ(11)) dut(.clk(clk),.rst(rst),.request(1'b0),.target(3'd0),.release_slot(1'b0),.cancel(1'b0),.display_valid(1'b0),.display_image(3'd0),.prefetch_pause(1'b0),
 .audio_packet_active(1'b0),.audio_request_valid(1'b0),.requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),.write_ack(1'b0),.full(1'b0),.finish_toggle(1'b0),.sd_miso(1'b1));
photo_sd_cache_before #(.CLK_HZ(11)) reference(.clk(clk),.rst(rst),.request(1'b0),.target(3'd0),.release_slot(1'b0),.cancel(1'b0),.display_valid(1'b0),.display_image(3'd0),.prefetch_pause(1'b0),
 .audio_packet_active(1'b0),.audio_request_valid(1'b0),.requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),.write_ack(1'b0),.full(1'b0),.finish_toggle(1'b0),.sd_miso(1'b1));
`define DRIVE(I) force I.initialized=1;force I.bmp_ready=0;force I.found=0;force I.audio_found=0;force I.scan_done=0;force I.scaler_pixel=0;force I.scaler_fault=0;force I.write_en=0;force I.write_req=0;force I.load_ready=0;force I.scanning=scanning;force I.loading=loading;force I.sector_end=progress;force I.load_start=started;
initial begin `DRIVE(dut) `DRIVE(reference) end
integer i,checks=0,scan_timeouts=0,load_timeouts=0;reg [31:0] rng=32'h73c2fd51;
always @(posedge clk)begin #1;
 if(!rst)begin
  if({dut.timer,dut.scanned,dut.scan_complete,dut.abort_op,dut.error,dut.cache_valid}!=={reference.timer,reference.scanned,reference.scan_complete,reference.abort_op,reference.error,reference.cache_valid})$fatal(1,"media watchdog changed cycle %d",checks);
  if(dut.due_scan!==(dut.timer>=220) || dut.due_load!==({32'd0,dut.timer}>=330))$fatal(1,"predicted threshold mismatch timer=%h flags=%b/%b limits=%d/%d",dut.timer,dut.due_scan,dut.due_load,dut.SCAN_LIMIT,dut.LOAD_LIMIT);
  checks=checks+1;if(dut.due_scan)scan_timeouts=scan_timeouts+1;if(dut.due_load)load_timeouts=load_timeouts+1;
 end
end
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(i=0;i<64000;i=i+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(i<2000)begin scanning=1;loading=0;progress=0;started=0;end
  else begin scanning=rng[0];loading=rng[1];progress=rng[7:2]==0;started=rng[13:8]==0;end
 end
 @(negedge clk);scanning=1;loading=0;progress=0;started=0;dut.timer=32'hfffffffc;reference.timer=32'hfffffffc;dut.due_scan=1;dut.due_load=1;
 repeat(12)@(negedge clk);rst=1;repeat(3)@(negedge clk);rst=0;scanning=0;loading=1;
 repeat(1000)@(negedge clk);
 if(scan_timeouts<100 || load_timeouts<100)$fatal(1,"threshold coverage missing");
 $display("PASS media watchdog pipeline: %0d clocks exact against original FSM, threshold/reset/hold/overlapping scan-load priority and 32-bit wrap",checks);$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
