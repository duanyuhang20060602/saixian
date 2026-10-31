`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0,ending=0;always #5 clk=~clk;
reg [7:0] data=0,records[0:4095];reg [7:0] address=0;
wire ready;wire [4:0] length;wire [31:0] word;
photo_sd_cache #(.TITLE_SD(1),.INDEPENDENT_TEXT(1)) dut(.clk(clk),.rst(rst),.title_ready(ready),.title_length(length),.title_address(address),.title_data(word),
 .request(1'b0),.target(3'd0),.release_slot(1'b0),.cancel(1'b0),.display_valid(1'b0),.display_image(3'd0),.prefetch_pause(1'b0),
 .audio_packet_active(1'b0),.audio_request_valid(1'b0),.requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),
 .write_ack(1'b0),.full(1'b0),.finish_toggle(1'b0),.sd_miso(1'b1));
integer i;reg [31:0] expected;reg[2:0] pc=0,mc=0;reg aa=0,ra=0,sc=0,sy=0,expected_stop;
initial begin
 $readmemh("title_records.hex",records);
 force dut.byte_valid=valid;force dut.byte_data=data;force dut.sector_end=ending;
 force dut.read_owner=2'd1;
 repeat(5)@(negedge clk);rst=0;
 // Drive the existing SD byte bus through its real owner qualification.
 // This catches a generate-local implicit owner shadowing the real register.
 for(i=0;i<2048;i=i+1)begin
  @(negedge clk);valid=1;data=records[i];
  if(i%512==511)begin
   @(negedge clk);valid=0;ending=1;@(negedge clk);ending=0;
  end
 end
 repeat(2)@(negedge clk);
 if(!ready || length!=4)$fatal(1,"actual SD cache did not route title scan bytes");
 for(i=0;i<256;i=i+1)begin
  address=i;repeat(2)@(negedge clk);
  expected={records[(i/64)*512+20+(i%64)*4],records[(i/64)*512+21+(i%64)*4],
   records[(i/64)*512+22+(i%64)*4],records[(i/64)*512+23+(i%64)*4]};
  if(length!==(i<128 ? 5'd4:5'd6))$fatal(1,"independent length mismatch");
  if(word!==expected)$fatal(1,"media font data routing mismatch %0d",i);
 end
 for(i=0;i<128;i=i+1)begin
  @(negedge clk);
  force dut.image_count=pc;force dut.audio_count=mc;force dut.award_available=aa;
  force dut.relief_available=ra;force dut.scanned=sc;force dut.scan_yield=sy;
  pc=(i&1) ? 3'd6:(i&2) ? 3'd1:3'd0;mc=i[2] ? 3'd5:3'd0;
  aa=i[3];ra=i[4];sc=i[5];sy=i[6];
  expected_stop=(pc!=0 || aa || ra) && (!sc || sy || (pc==6 && mc==5 && aa && ra && ready));
  @(posedge clk);@(negedge clk);
  if(dut.bmp.scan_stop!==expected_stop)$fatal(1,"scan-stop register changed complete-scan expression");
 end
 $display("PASS actual photo_sd_cache owner gating, generated storage hierarchy, independent title/ticker and all 256 words; physical SD/audio/decoders replaced by port shells");$finish;
end
initial begin #100000;$fatal(1,"SD media title timeout");end
endmodule
