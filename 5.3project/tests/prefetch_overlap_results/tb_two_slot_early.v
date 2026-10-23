`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,request=0,release_slot=0,cancel=0;
reg [2:0] target=0;wire ready,directory_ready,req,we;wire [1:0] slot,write_slot;wire [2:0] count;wire [3:0] error;wire [31:0] data;
reg finish_t=0;integer words=0,n;reg display_valid=0,prefetch_pause=0;reg [2:0] display_image=0;
photo_sd_cache #(.CLK_HZ(10000),.SCAN_MAX_SECTOR(16),.FRAME_WORDS(16),.DISPLAY_PIN(1),.FORWARD_ONLY(1),.EARLY_PREFETCH(1)) dut(
 .display_valid(display_valid),.display_image(display_image),.prefetch_pause(prefetch_pause),
 .audio_packet_active(1'b0),.audio_request_valid(1'b0),.requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),
 .clk(clk),.rst(rst),.request(request),.target(target),.release_slot(release_slot),.cancel(cancel),
 .ready(ready),.ready_slot(slot),.image_count(count),.error(error),.directory_ready(directory_ready),
 .write_slot(write_slot),.write_req(req),.write_ack(req),.full(1'b0),.write_en(we),.write_data(data),.finish_toggle(finish_t),
 .sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1));
always @(posedge clk)begin
 if(req)words<=0;
 if(req && write_slot>1)$fatal(1,"B used removed third slot");
 if(we)begin
  if(ready && write_slot==slot)$fatal(1,"prefetch overwrites transmit lock");
  words<=words+1;if(words==15)finish_t<=~finish_t;
 end
end
task choose;
 input [2:0] id;
 begin @(negedge clk);target=id;request=1;@(negedge clk);request=0;wait(ready);
  if(dut.cache_id[slot]!=id || error!=0)$fatal(1,"cache returns wrong image");
  repeat(100)@(negedge clk);
  release_slot=1;@(negedge clk);release_slot=0;wait(!ready);
 end
endtask
initial begin
 repeat(5)@(negedge clk);rst=0;wait(directory_ready);if(count!=6)$fatal(1,"sixth BMP excluded");
 choose(0);repeat(500)@(negedge clk);
 if(dut.cache_valid!=3 || !dut.current_hit || !dut.next_hit)$fatal(1,"current+next slots not populated");
 for(n=0;n<18;n=n+1)choose(n%6);
 choose(5);choose(0);choose(5);
 // Settings must pin the actual HDMI photo while a different slot transmits.
 display_valid=1;display_image=5;prefetch_pause=1;
 wait(dut.pin_hit);repeat(300)@(negedge clk);
 @(negedge clk);target=2;request=1;@(negedge clk);request=0;wait(ready);
 repeat(500)@(negedge clk);if(!dut.pin_hit || dut.cache_id[slot]!=2)$fatal(1,"settings pin or transmit lock overwritten");
 release_slot=1;@(negedge clk);release_slot=0;wait(!ready);
 // Failed incoming images stay unpublished and must not disturb the pinned one.
 @(negedge clk);target=4;request=1;@(negedge clk);request=0;wait(dut.loading);
 force dut.scaler_fault=1'b1;repeat(2)@(negedge clk);release dut.scaler_fault;
 wait(error==2);if(ready || !dut.pin_hit)$fatal(1,"failed cache load published or pin lost");
 repeat(10)@(negedge clk);choose(4);
 prefetch_pause=0;display_valid=0;repeat(500)@(negedge clk);
 $display("PASS B two external SDRAM slots: six-image directory, 21 wrapped navigations, current+next prefetch, locked transmit, actual-HDMI settings pin, failed-load quarantine and retry; A slots unchanged");$finish;
end
initial begin #1000000;$fatal(1,"cache timeout error=%d ready=%d loading=%d words=%d",error,ready,dut.loading,dut.words);end
endmodule

// Model only the SD source at the scheduler boundary. Actual BMP parsing,
// padding and scaling are tested separately using the immutable photo core.
module bmp_read(input clk,rst,op_abort,output ready,input scan_start,scan_stop,scan_resume,output scan_exhausted,scan_found_dlt,
 input [31:0] scan_start_sector,scan_max_sector,input [2:0] scan_target_count,
 output reg scan_done,scan_found_valid,output reg [31:0] scan_found_sector,
 output [2:0] scan_found_total,output [15:0] scan_found_width,scan_found_height,output scan_found_sprint,
 output audio_found_valid,output [2:0] audio_found_index,output [31:0] audio_found_sector,audio_found_bytes,
 input load_start,input [31:0] load_sector,input sd_init_done,output [3:0] state_code,
 input [15:0] bmp_width,bmp_height,output reg write_req,input write_req_ack,
 output sd_sec_read,output [31:0] sd_sec_read_addr,input [7:0] sd_sec_read_data,
 input sd_sec_read_data_valid,sd_sec_read_end,output reg bmp_data_wr_en,output reg [23:0] bmp_data,output scaler_fault_o);
reg [2:0] state=0;reg [5:0] pixels=0,scan_index=0;reg [3:0] pace=0;
assign scan_exhausted=scan_index==6;assign scan_found_dlt=0;assign ready=state==0;assign scan_found_total=0;assign scan_found_width=1280;assign scan_found_height=720;
assign scan_found_sprint=scan_index==5;assign audio_found_valid=0;assign audio_found_index=0;assign audio_found_sector=0;assign audio_found_bytes=0;
assign state_code=state;assign sd_sec_read=0;assign sd_sec_read_addr=0;assign scaler_fault_o=0;
always @(posedge clk)begin
 if(rst || op_abort)begin state<=0;scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;write_req<=0;bmp_data_wr_en<=0;bmp_data<=0;end
 else begin
  scan_found_valid<=0;bmp_data_wr_en<=0;
  case(state)
   0:if(scan_start)begin state<=1;scan_index<=0;scan_done<=0;end
     else if(load_start)begin state<=2;write_req<=1;pixels<=0;end
   1:begin
    if(scan_index<6)begin scan_found_valid<=1;scan_found_sector<=scan_index*16;scan_index<=scan_index+1;end
    else begin scan_done<=1;state<=0;end
   end
   2:if(write_req_ack)begin write_req<=0;state<=3;pace<=0;end
   3:begin
    pace<=pace+1;
    if(pace==4)begin
     bmp_data_wr_en<=1;bmp_data<={load_sector[7:0],pixels[5:0],10'd0};pixels<=pixels+1;pace<=0;
     if(pixels==31)state<=4;
    end
   end
   4:state<=0;
  endcase
 end
end
endmodule
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248,SPI_HIGH_SPEED_DIV=2,READ_MULTIBLOCK=1,FAST_READ_STREAM=1)(
 input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,output sd_init_done,output [2:0] init_stage,
 input sd_sec_read,input [31:0] sd_sec_read_addr,output [7:0] sd_sec_read_data,output sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input [31:0] sd_sec_write_addr,input [7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end);
assign sd_init_done=!rst;assign init_stage=0;assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;assign sd_sec_read_end=0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
