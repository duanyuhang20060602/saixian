`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0,ending=0;always #5 clk=~clk;
reg [7:0] data=0,records[0:4095];reg [6:0] address=0;
wire ready;wire [4:0] length;wire [31:0] word;
photo_sd_cache #(.TITLE_SD(1)) dut(.clk(clk),.rst(rst),.title_ready(ready),.title_length(length),.title_address(address),.title_data(word),
 .request(1'b0),.target(3'd0),.release_slot(1'b0),.cancel(1'b0),.display_valid(1'b0),.display_image(3'd0),.prefetch_pause(1'b0),
 .audio_packet_active(1'b0),.audio_request_valid(1'b0),.requested_audio_epoch(8'd0),.requested_audio_track(3'd0),.audio_fifo_read(1'b0),
 .write_ack(1'b0),.full(1'b0),.finish_toggle(1'b0),.sd_miso(1'b1));
integer i;reg [31:0] expected;
initial begin
 $readmemh("title_records.hex",records);
 force dut.byte_valid=valid;force dut.byte_data=data;force dut.sector_end=ending;
 force dut.read_owner=2'd1;
 repeat(5)@(negedge clk);rst=0;
 // Drive the existing SD byte bus through its real owner qualification.
 // This catches a generate-local implicit owner shadowing the real register.
 for(i=0;i<1024;i=i+1)begin
  @(negedge clk);valid=1;data=records[i];
  if(i%512==511)begin
   @(negedge clk);valid=0;ending=1;@(negedge clk);ending=0;
  end
 end
 repeat(2)@(negedge clk);
 if(!ready || length!=16)$fatal(1,"actual SD cache did not route title scan bytes");
 for(i=0;i<128;i=i+1)begin
  address=i;repeat(2)@(negedge clk);
  expected={records[(i/64)*512+20+(i%64)*4],records[(i/64)*512+21+(i%64)*4],
   records[(i/64)*512+22+(i%64)*4],records[(i/64)*512+23+(i%64)*4]};
  if(word!==expected)$fatal(1,"media font data routing mismatch %0d",i);
 end
 $display("PASS actual photo_sd_cache owner gating, generated storage hierarchy, complete title and all 128 words; physical SD/audio/decoders replaced by port shells");$finish;
end
initial begin #100000;$fatal(1,"SD media title timeout");end
endmodule
