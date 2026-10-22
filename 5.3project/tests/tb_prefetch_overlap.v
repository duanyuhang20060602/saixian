`timescale 1ns/1ps
// Two real schedulers share identical deterministic SD models and transmit
// durations. Only EARLY_PREFETCH differs. Time is model cycles, not board ms.
module prefetch_client #(parameter EARLY=0)(output reg done=0,output integer wait_cycles,overlaps);
reg clk=0;always #5 clk=~clk;
reg rst=1,request=0,release_slot=0,cancel=0,finish_toggle=0;
reg [2:0] target=0;
wire ready,write_req,write_en,directory_ready;wire [1:0] ready_slot,write_slot;
wire [2:0] count;wire [3:0] error;wire [31:0] data;
integer words=0,i,step;
reg measuring=0;
photo_sd_cache #(.CLK_HZ(10000),.SCAN_MAX_SECTOR(16),.FRAME_WORDS(16),.DISPLAY_PIN(1),.FORWARD_ONLY(1),.EARLY_PREFETCH(EARLY)) dut(
 .clk(clk),.rst(rst),.request(request),.target(target),.release_slot(release_slot),.cancel(cancel),
 .display_valid(1'b0),.display_image(3'd0),.prefetch_pause(1'b0),
 .audio_packet_active(1'b0),.audio_request_valid(1'b0),.requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),
 .ready(ready),.ready_slot(ready_slot),.image_count(count),.error(error),.directory_ready(directory_ready),
 .write_slot(write_slot),.write_req(write_req),.write_ack(write_req),.full(1'b0),.write_en(write_en),.write_data(data),.finish_toggle(finish_toggle),
 .sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1));
function [15:0] expected_pixel;
 input [2:0] image;input integer pixel;
 reg [7:0] sector;reg [23:0] rgb;
 begin sector=image*16;rgb={sector,pixel[5:0],10'd0};expected_pixel={rgb[23:19],rgb[15:10],rgb[7:3]};end
endfunction
always @(posedge clk)begin
 if(write_req)words<=0;
 if(write_req && write_slot>1)$fatal(1,"used a third B slot");
 if(write_en)begin
  if(ready && write_slot==ready_slot)$fatal(1,"overwrote locked transmit slot");
  if(data!=={expected_pixel(dut.load_image,words*2),expected_pixel(dut.load_image,words*2+1)})
   $fatal(1,"image payload changed during overlapping cache load");
  words<=words+1;
  if(words==15)finish_toggle<=~finish_toggle;
 end
 if(measuring && write_req && ready)overlaps=overlaps+1;
end
task choose;
 input [2:0] image;
 begin
  @(negedge clk);target=image;request=1;@(negedge clk);request=0;
  while(!ready)begin @(negedge clk);if(measuring)wait_cycles=wait_cycles+1;end
  if(dut.cache_id[ready_slot]!=image || error!=0)$fatal(1,"wrong image or cache error");
  repeat(80)@(negedge clk); // Fixed model transfer time, same for both clients.
  release_slot=1;@(negedge clk);release_slot=0;wait(!ready);
 end
endtask
initial begin
 wait_cycles=0;overlaps=0;
 repeat(5)@(negedge clk);rst=0;wait(directory_ready);
 choose(0);repeat(500)@(negedge clk);measuring=1;
 for(step=1;step<=18;step=step+1)choose(step%6);
 measuring=0;done=1;
end
endmodule

module tb_prefetch_overlap;
wire old_done,new_done;wire signed [31:0] old_wait,new_wait,old_overlap,new_overlap;
prefetch_client #(.EARLY(0)) baseline(old_done,old_wait,old_overlap);
prefetch_client #(.EARLY(1)) optimized(new_done,new_wait,new_overlap);
initial begin
 wait(old_done && new_done);
 if(new_overlap==0 || old_overlap!=0)$fatal(1,"did not demonstrate earlier overlap: %d/%d",old_overlap,new_overlap);
 if(new_wait>=old_wait || new_wait*100>old_wait*75)$fatal(1,"insufficient scheduler improvement %d -> %d",old_wait,new_wait);
 $display("PASS overlap A/B scheduler comparison: baseline_wait=%0d optimized_wait=%0d cycles, baseline_overlap=%0d optimized_overlap=%0d, 18 switches and wraps, locked slots and pixel payload checked",old_wait,new_wait,old_overlap,new_overlap);
 $finish;
end
initial begin #1000000;$fatal(1,"comparison timeout");end
endmodule
