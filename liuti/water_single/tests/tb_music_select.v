`timescale 1ns/1ps
module tb;
localparam OLD_BYTES=28287196,NEW_BYTES=35230400;
localparam NEXT_HEADER=1+(OLD_BYTES+511)/512;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0,valid=0,ending=0;reg[7:0] byte_data=0;
wire req,done,found;wire[31:0] sector,found_sector,found_bytes;wire[2:0] found_index;
bmp_read #(.NATIVE_720_ONLY(1),.AUDIO_EXPECTED_BYTES(NEW_BYTES)) d(
 .clk(clk),.rst(rst),.op_abort(1'b0),.scan_start(start),.scan_stop(1'b0),.scan_start_sector(32'd0),
 .scan_max_sector(NEXT_HEADER+1),.scan_target_count(3'd5),.scan_done(done),
 .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),.bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),
 .sd_sec_read(req),.sd_sec_read_addr(sector),.sd_sec_read_data(byte_data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(ending),
 .audio_found_valid(found),.audio_found_index(found_index),.audio_found_sector(found_sector),.audio_found_bytes(found_bytes));
integer requests=0,tracks=0,i;reg[7:0] header[0:511],selected_header[0:511];reg[31:0] bytes;
task le32;input integer index,value;integer j;begin for(j=0;j<4;j=j+1)header[index+j]=value>>(8*j);end endtask
always @(posedge clk)if(!rst&&found)begin
 if(found_index!=0||found_sector!=NEXT_HEADER+1||found_bytes!=NEW_BYTES)$fatal(1,"selected old AUD instead of TIMEBRK: index%0d sector%0d bytes%0d",found_index,found_sector,found_bytes);
 tracks=tracks+1;
end
initial begin
 $readmemh("selected_audio_header.hex",selected_header);
 repeat(4)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 forever begin
  wait(req);if(sector!==(requests==0 ? 0:NEXT_HEADER))$fatal(1,"AUD payload was not skipped correctly: %0d",sector);
  bytes=requests==0 ? OLD_BYTES:NEW_BYTES;requests=requests+1;
  for(i=0;i<512;i=i+1)header[i]=0;
  header[0]="S";header[1]="X";header[2]="A";header[3]="U";header[4]="D";header[5]="0";header[6]="0";header[7]="1";
  le32(8,bytes);le32(12,48000);header[16]=16;header[18]=2;le32(20,512);
  if(requests==2)for(i=0;i<512;i=i+1)header[i]=selected_header[i];
  for(i=0;i<512;i=i+1)begin @(negedge clk);byte_data=header[i];valid=1;@(negedge clk);valid=0;end
  @(negedge clk);ending=1;@(negedge clk);ending=0;wait(!req);
  if(requests==2)begin
   wait(done);repeat(5)@(negedge clk);
   if(tracks!=1)$fatal(1,"music selection count %0d",tracks);
   $display("PASS selected music: stale BGM1 header ignored, both AUD payloads skipped, actual TIMEBRK header published as track0 with exact sector and length");$finish;
  end
 end
end
initial begin #100000;$fatal(1,"music scan timeout");end
endmodule
