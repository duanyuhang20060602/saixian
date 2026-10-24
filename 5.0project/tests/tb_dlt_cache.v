`timescale 1ns/1ps
// Real directory/cache/arbitration/decoder/packing; sector and SDRAM-write
// interfaces modeled. An audio header precedes the DLT and music sectors are
// requested during decoding. A cache slot is publishable only after drain.
module tb_dlt_cache;
reg clk=0;always #5 clk=~clk;
reg rst=1,request=0,release_slot=0,hc_request=0;
wire award_available;wire hc,ready,directory_ready,write_req,write_en,top_down;wire [31:0] write_data;
wire [2:0] count;wire [3:0] error;wire [15:0] width,height;
reg [2:0] ack=0;reg finish=0;integer stored=0,mode,total,audio_reads=0;
photo_sd_cache #(.SCAN_MAX_SECTOR(2)) dut(
 .display_valid(1'b0),.display_image(3'd0),.prefetch_pause(1'b0),.audio_packet_active(1'b0),
 .audio_request_valid(1'b0),.requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),
 .clk(clk),.rst(rst),.request(request),.target(3'd6),.release_slot(release_slot),.cancel(1'b0),
 .award_available(award_available),.ready(ready),.image_count(count),.error(error),.directory_ready(directory_ready),.ready_source_width(width),.ready_source_height(height),
 .write_req(write_req),.write_top_down(top_down),.write_ack(ack[2]),.full(1'b0),.write_en(write_en),.write_data(write_data),
 .finish_toggle(finish),.sd_miso(1'b0));
defparam dut.dlt.PIXEL_GAP=1;
function [23:0] expand;input [15:0] p;begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
reg [31:0] expected;reg [23:0] a,b;
always @(posedge clk)begin
 if(rst)begin ack<=0;finish<=0;stored<=0;audio_reads<=0;end
 else begin
  ack<={ack[1:0],write_req};if(write_req)stored<=0;
  if(dut.sector_end && dut.read_owner==2)audio_reads<=audio_reads+1;
  if(error)$fatal(1,"DLT cache error=%0d engine=%0d",error,dut.dlt.error);
  if(write_en)begin
   if(!top_down)$fatal(1,"DLT was assigned BMP row orientation");
   a=expand(16'h3412);b=expand(16'h8910);
   if(!hc)expected=32'h34128910;
   else case(stored%3)0:expected={a,b[23:16]};1:expected={b[15:0],a[23:8]};2:expected={a[7:0],b};endcase
   if(write_data!==expected)$fatal(1,"DLT cache word/tag order color=%0b word=%0d",hc,stored);
   stored<=stored+1;
   if(stored==(hc ? 691199:460799))finish<=~finish;
  end
  if(ready && (!dut.dlt_done || stored!=(hc ? 691200:460800)))$fatal(1,"cache published before CRC/write drain");
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;wait(directory_ready);
 if(count!=0 || !award_available)$fatal(1,"original DLT not catalogued after AUD");
 for(mode=0;mode<2;mode=mode+1)begin
  if(mode==1)begin
   release_slot=1;@(negedge clk);release_slot=0;hc_request=1;wait(hc);repeat(5)@(negedge clk);
  end
  @(negedge clk);request=1;@(negedge clk);request=0;wait(ready);repeat(5)@(negedge clk);
  if(width!==16'h8500 || height!==720 || !dut.directory_dlt[6])$fatal(1,"DLT cache metadata lost");
 end
 if(audio_reads==0)$fatal(1,"audio arbitration not exercised");
 $display("PASS real DLT discovery after AUD, sector audio interleaving, RGB565/RGB888 cache fills, top-down tag order, publish gated on complete decode and write drain, audio sectors=%0d",audio_reads);$finish;
end
initial begin #150000000;$fatal(1,"DLT cache timeout state=%0d engine=%0d words=%0d",dut.bmp.state,dut.dlt.state,stored);end
endmodule

// Native sector interface only, not SPI electrical/controller verification.
module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248,SPI_HIGH_SPEED_DIV=2,READ_MULTIBLOCK=1,FAST_READ_STREAM=1)(
 input clk,rst,SD_MISO,output SD_nCS,SD_DCLK,SD_MOSI,output reg sd_init_done,
 output [2:0] init_stage,input sd_sec_read,input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data,output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write,input [31:0] sd_sec_write_addr,input [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end);
reg [7:0] fixture[0:2047];reg active=0,wait_low=0;reg [31:0] sector=0;integer index=0;
initial $readmemh("tests/results/dlt_fault11.hex",fixture);
assign SD_nCS=1;assign SD_DCLK=clk;assign SD_MOSI=0;assign init_stage=4;
assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
function [7:0] at;input [31:0] s;input integer n;
 begin
  at=0;
  if(s>=2 && s<=5)at=fixture[(s-2)*512+n];
  else if(s==0)case(n)
   0:at="S";1:at="X";2:at="A";3:at="U";4:at="D";5,6:at="0";7:at="1";
   8:at=4;12:at=8'h80;13:at=8'hbb;16:at=16;18:at=2;
  endcase
 end
endfunction
always @(posedge clk)begin
 if(rst)begin sd_init_done<=0;active<=0;wait_low<=0;index<=0;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;sd_sec_read_data<=0;end
 else begin
  sd_init_done<=1;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
  if(!sd_sec_read)wait_low<=0;
  if(!active && !wait_low && sd_sec_read)begin active<=1;sector<=sd_sec_read_addr;index<=0;end
  else if(active)begin
   sd_sec_read_data_valid<=1;sd_sec_read_data<=at(sector,index);index<=index+1;
   if(index==511)begin active<=0;wait_low<=1;sd_sec_read_end<=1;end
  end
 end
end
endmodule
module photo_audio_fifo(input clk,rst,write_en,input [31:0] write_data,input read_en,
 output [31:0] data,output [13:0] used,output empty,full);
assign data=0;assign used=0;assign empty=1;assign full=0;
endmodule
module photo_sd_audio_stream(input clk,rst,enable,input [31:0] start_sector,data_bytes,input [13:0] fifo_wrusedw,
 output reg sd_sec_read,output [31:0] sd_sec_read_addr,input [7:0] sd_sec_read_data,
 input sd_sec_read_data_valid,sd_sec_read_end,output pcm_we,output [31:0] pcm_word);
integer cooldown=0;
assign sd_sec_read_addr=start_sector;assign pcm_we=0;assign pcm_word=0;
always @(posedge clk)begin
 if(rst)begin sd_sec_read<=0;cooldown<=0;end
 else if(sd_sec_read_end)begin sd_sec_read<=0;cooldown<=10000;end
 else if(cooldown>0)cooldown<=cooldown-1;
 else if(enable)sd_sec_read<=1;
end
endmodule
