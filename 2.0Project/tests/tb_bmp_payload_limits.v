`timescale 1ns/1ps
// The accepted-header size limit must bound the byte counter. Check header
// rejection and inclusive/exclusive payload limits, including sector padding.
module tb_bmp_payload_limits;
reg clk=0; always #5 clk=~clk;
reg rst=1, valid=0, abort=0;
bmp_read dut(.clk(clk),.rst(rst),.op_abort(abort),.scan_start(1'b0),.scan_stop(1'b0),
 .scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd0),
 .load_start(1'b0),.load_sector(32'd0),.sd_init_done(1'b1),
 .bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),
 .sd_sec_read_data(8'h55),.sd_sec_read_data_valid(valid),.sd_sec_read_end(1'b0));
integer offset, delta;
reg [31:0] reference;
initial begin
 repeat(3) @(negedge clk); rst=0;
 force dut.header_0=8'h42; force dut.header_1=8'h4d;
 force dut.dib_header_size=40; force dut.planes=1;
 force dut.pixel_offset=54; force dut.file_len=8388608;
 #1; if(!dut.header_basic_ok) $fatal(1,"8 MiB BMP incorrectly rejected");
 force dut.file_len=8388609;
 #1; if(dut.header_basic_ok) $fatal(1,"oversized BMP was admitted");
 force dut.file_len=32'h01000036;
 #1; if(dut.header_basic_ok) $fatal(1,"high-byte file length was admitted");
 force dut.file_len=8388608; force dut.pixel_offset=8388608;
 #1; if(dut.header_basic_ok) $fatal(1,"offset at file end was admitted");
 force dut.pixel_offset=54; force dut.state=3'd4;
 valid=1;
 // 54-byte header boundary, 64 KiB carry, maximum file end and padding.
 for(offset=0;offset<3;offset=offset+1) begin
  for(delta=-2;delta<514;delta=delta+1) begin
   @(negedge clk);
   case(offset)
    0:reference=54+delta;
    1:reference=65536+delta;
    2:reference=8388608+delta;
   endcase
   dut.bmp_len_cnt=reference;
   #1;
   if(dut.bmp_data_valid !== ((reference>=54)&&(reference<8388608)))
    $fatal(1,"BMP payload boundary mismatch at byte %0d",reference);
   @(negedge clk);
   if(dut.bmp_len_cnt!==reference+1)
    $fatal(1,"BMP byte count overflow at %0d",reference);
  end
 end
 abort=1;@(negedge clk);
 if(dut.bmp_len_cnt!=0) $fatal(1,"BMP byte counter not reset on abort");
 $display("PASS BMP size rejection, payload boundaries, 64 KiB carry, 8 MiB end and sector padding");
 $finish;
end
initial begin #1000000;$fatal(1,"BMP payload test timeout");end
endmodule
