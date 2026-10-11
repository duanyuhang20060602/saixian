`timescale 1ns/1ps
module tb_scan_target_equivalence;
reg clk=0;always #5 clk=~clk;
reg rst=1,ending=0;reg [31:0] base,len,max_sector;
reg [2:0] found,audios,target;
wire [31:0] address;
wire done,audio_valid;wire [31:0] audio_bytes;
bmp_read dut(.clk(clk),.rst(rst),.op_abort(1'b0),.scan_start(1'b0),.scan_stop(1'b0),
 .scan_start_sector(32'd0),.scan_max_sector(max_sector),.scan_target_count(target),
 .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),.bmp_width(16'd1280),.bmp_height(16'd720),
 .write_req_ack(1'b0),.sd_sec_read_data(8'd0),.sd_sec_read_data_valid(1'b0),.sd_sec_read_end(ending),
 .sd_sec_read_addr(address),.scan_done(done),.audio_found_valid(audio_valid),.audio_found_bytes(audio_bytes));
integer i;reg [31:0] expected;reg stop;
initial begin
 repeat(3)@(negedge clk);rst=0;
 force dut.audio_header_ok=1;force dut.audio_data_len=len;
 force dut.audio_found_count=audios;force dut.scan_found_total=found;
 for(i=0;i<5000;i=i+1)begin
  base=$random;len=$random;max_sector=$random;found=i%6;audios=i%6;target=(i/6)%6;
  case(i%10)0:len=0;1:len=1;2:len=511;3:len=512;4:len=513;5:len=32'hffffffff;default:;endcase
  expected=base+32'd1+((len+32'd511)>>9);
  if(i%3==0)max_sector=expected;
  if(i%3==1)max_sector=expected-1;
  stop=(found>=target && audios>=4) || expected>max_sector;
  dut.state=3'd1;dut.scan_sector=base;dut.scan_done=0;
  // A real sector supplies 512 bytes; its length settles by byte 12.
  repeat(6)@(negedge clk);
  ending=1;@(negedge clk);ending=0;@(negedge clk);
  if(address!==expected || done!==stop || (audios<5 && (!audio_valid || audio_bytes!==len)))
   $fatal(1,"scan target mismatch base=%h length=%h max=%h got=%h/%b expected=%h/%b",base,len,max_sector,address,done,expected,stop);
  dut.state=0;
 end
 $display("PASS prepared AUD scan target: 5000 full-width cases, sector boundaries, wrapped lengths/addresses, current scan limit and found counts");$finish;
end
endmodule
