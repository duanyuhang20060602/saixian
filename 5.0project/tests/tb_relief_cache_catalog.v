`timescale 1ns/1ps
// Production scheduler, packer and cache. SD/BMP/DLT are modeled at the
// established scheduler boundary, including cooperative scan-stop/resume and
// full-length 691200-word award writes; no image decoder is substituted in RTL.
module tb;
parameter REVERSE=0;
parameter PAUSED=0;
reg clk=0;always #5 clk=~clk;reg rst=1,request=0,release_slot=0;
reg[2:0] target=0;wire ready,directory_ready,req,we;wire[1:0] slot,write_slot;
wire[2:0] count;wire[3:0] error;wire[31:0] data;wire old,new_mode,complete;
wire[15:0] width,height;wire write_award;
reg finish_t=0,pause_prefetch=0;integer words=0,loads=0;
photo_sd_cache #(.CLK_HZ(100000000),.SCAN_MAX_SECTOR(40000),.FRAME_WORDS(16),.DISPLAY_PIN(1),.FORWARD_ONLY(1)) dut(
 .display_valid(1'b0),.display_image(3'd0),.prefetch_pause(pause_prefetch),.audio_packet_active(1'b0),.audio_request_valid(1'b0),
 .requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),
 .clk(clk),.rst(rst),.request(request),.target(target),.release_slot(release_slot),.cancel(1'b0),
 .ready(ready),.ready_slot(slot),.image_count(count),.error(error),.directory_ready(directory_ready),
 .award_available(old),.relief_available(new_mode),.award_scan_complete(complete),.ready_source_width(width),.ready_source_height(height),
 .write_slot(write_slot),.write_req(req),.write_ack(req),.full(1'b0),.write_en(we),.write_data(data),.write_award(write_award),.finish_toggle(finish_t),
 .sd_ncs(),.sd_dclk(),.sd_mosi(),.sd_miso(1'b1));
defparam dut.bmp.REVERSE=REVERSE;
always @(posedge clk)begin
 if(req)begin words<=0;loads<=loads+1;end
 if(we)begin
  if(ready && write_slot==slot)$fatal(1,"award load overwrote locked transmit slot");
  words<=words+1;
  if(words==(write_award ? 691199:15))finish_t<=~finish_t;
 end
 if(error)$fatal(1,"cache error %0d",error);
end
task choose;input[2:0] id;begin
 @(negedge clk);target=id;request=1;@(negedge clk);request=0;wait(ready);
 if(dut.cache_id[slot]!=id || height!=720 || width!=(id==7 ? 16'hc500:id==6 ? 16'h8500:16'd1280))
  $fatal(1,"cache id/source-size mismatch id=%0d width=%h",id,width);
 repeat(16)@(negedge clk);release_slot=1;@(negedge clk);release_slot=0;wait(!ready);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;wait(directory_ready);choose(0);
 pause_prefetch=PAUSED;
 wait(complete);repeat(5)@(negedge clk);
 if(count!=6 || !old || !new_mode || dut.directory_dlt!=8'hc0)$fatal(1,"six photos plus separate old/new award entries");
 if(dut.directory[6]!=(REVERSE ? 212:196) || dut.directory[7]!=(REVERSE ? 196:212))
  $fatal(1,"duplicate award header replaced original catalog entry");
 if(PAUSED)begin
  if(!dut.current_hit || dut.bmp.resumes<1)$fatal(1,"paused catalog lost current image or did not resume");
  $display("PASS paused-prefetch cache catalog: six photos, both award types and duplicates discovered while current photo is retained; reverse=%0d",REVERSE);$finish;
 end
 choose(7);choose(6);choose(0);choose(6);choose(7);
 if(dut.bmp.resumes<1 || dut.dlt.starts<2)$fatal(1,"cache scan-resume/full-award-load paths not exercised");
 $display("PASS cache: six photos retained; independent id6/id7, duplicate headers, source metadata, scan resume, complete 691200-word transfers, locked slots and navigation; reverse=%0d",REVERSE);$finish;
end
initial begin #120000000;$fatal(1,"cache catalog timeout count=%0d old/new=%b%b complete=%b loading=%b words=%0d",count,old,new_mode,complete,dut.loading,words);end
endmodule

module bmp_read #(parameter REVERSE=0)(input clk,rst,op_abort,output ready,input scan_start,scan_stop,scan_resume,
 output reg scan_exhausted,scan_found_dlt,input[31:0] scan_start_sector,scan_max_sector,input[2:0] scan_target_count,
 output reg scan_done,scan_found_valid,output reg[31:0] scan_found_sector,output[2:0] scan_found_total,
 output reg[15:0] scan_found_width,output[15:0] scan_found_height,output scan_found_sprint,
 output audio_found_valid,output[2:0] audio_found_index,output[31:0] audio_found_sector,audio_found_bytes,
 input load_start,input[31:0] load_sector,input sd_init_done,output[3:0] state_code,input[15:0] bmp_width,bmp_height,
 output reg write_req,input write_req_ack,output sd_sec_read,output[31:0] sd_sec_read_addr,input[7:0] sd_sec_read_data,
 input sd_sec_read_data_valid,sd_sec_read_end,output reg bmp_data_wr_en,output reg[23:0] bmp_data,output scaler_fault_o);
reg[2:0] state=0;integer index=0,pixels=0,pace=0,resumes=0;
assign ready=state==0;assign scan_found_total=0;assign scan_found_height=720;assign scan_found_sprint=0;
assign audio_found_valid=0;assign audio_found_index=0;assign audio_found_sector=0;assign audio_found_bytes=0;
assign state_code=state;assign sd_sec_read=0;assign sd_sec_read_addr=0;assign scaler_fault_o=0;
always @(posedge clk)begin
 if(rst || op_abort)begin state<=0;scan_done<=0;scan_exhausted<=0;scan_found_valid<=0;scan_found_dlt<=0;
  scan_found_sector<=0;scan_found_width<=0;write_req<=0;bmp_data_wr_en<=0;bmp_data<=0;index<=0;resumes<=0;end
 else begin
  scan_found_valid<=0;bmp_data_wr_en<=0;
  case(state)
   0:if(scan_start)begin state<=1;index<=0;scan_done<=0;pace<=0;end
     else if(scan_resume)begin state<=1;scan_done<=0;pace<=0;resumes<=resumes+1;end
     else if(load_start)begin state<=2;write_req<=1;pixels<=0;end
   1:begin
    if(scan_stop)begin state<=0;scan_done<=1;end
    else if(pace==8)begin
     pace<=0;
     if(index<10)begin
      scan_found_valid<=1;scan_found_sector<=100+index*16;scan_found_dlt<=index>=6;
      scan_found_width<=index<6 ? 16'd1280:((index%2==1)^REVERSE) ? 16'hc500:16'h8500;
      index<=index+1;
     end else begin scan_done<=1;scan_exhausted<=1;state<=0;end
    end else pace<=pace+1;
   end
   2:if(write_req_ack)begin write_req<=0;state<=3;end
   3:begin bmp_data_wr_en<=1;bmp_data<={load_sector[7:0],pixels[5:0],10'd0};pixels<=pixels+1;if(pixels==31)state<=4;end
   4:state<=0;
  endcase
 end
end
endmodule
module photo_dlt_reader(input clk,rst,start,input[31:0] start_sector,output ready,done,output[3:0] error,
 output reg write_req,input write_ack,full,output reg pixel_valid,output reg[23:0] pixel,
 output req,output[31:0] sector,input byte_valid,input[7:0] byte_data,input block_end);
reg[1:0] state=0;integer pixels=0,starts=0;
assign ready=state==0;assign done=state==0;assign error=0;assign req=0;assign sector=0;
always @(posedge clk)begin
 if(rst)begin state<=0;pixels<=0;write_req<=0;pixel_valid<=0;pixel<=0;starts<=0;end
 else begin
  pixel_valid<=0;
  case(state)
   0:if(start)begin state<=1;write_req<=1;pixels<=0;starts<=starts+1;end
   1:if(write_ack)begin write_req<=0;state<=2;end
   2:if(!full)begin pixel_valid<=1;pixel<={start_sector[7:0],pixels[7:0],pixels[7:0]};pixels<=pixels+1;
    if(pixels==1382399)state<=3;
   end
   3:state<=0;
  endcase
 end
end
endmodule
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248,SPI_HIGH_SPEED_DIV=2,READ_MULTIBLOCK=1,FAST_READ_STREAM=1)(
 input clk,rst,output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO,output sd_init_done,output[2:0] init_stage,
 input sd_sec_read,input[31:0] sd_sec_read_addr,output[7:0] sd_sec_read_data,output sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input[31:0] sd_sec_write_addr,input[7:0] sd_sec_write_data,output sd_sec_write_data_req,sd_sec_write_end);
assign sd_init_done=!rst;assign init_stage=0;assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=0;
assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;assign sd_sec_read_end=0;assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
