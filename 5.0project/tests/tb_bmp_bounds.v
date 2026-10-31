`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0;always #5 clk=~clk;
reg[31:0] offset=54,length=118,position=0;
reg[2:0] forced_state=3;
integer i,j,gap,checks=0;
bmp_read dut(.clk(clk),.rst(rst),.op_abort(1'b0),.scan_start(1'b0),.scan_stop(1'b0),
 .scan_resume(1'b0),.load_start(1'b0),.sd_init_done(1'b1),.sd_sec_read_data_valid(valid),
 .sd_sec_read_data(8'd0),.sd_sec_read_end(1'b0),.write_req_ack(1'b0),
 .bmp_width(16'd1280),.bmp_height(16'd720));
initial begin
 force dut.pixel_offset=offset;force dut.file_len=length;
 force dut.bmp_len_cnt=position;force dut.state=forced_state;
end
task step;
 input integer present;
 begin
  @(negedge clk);valid=present;#1;
  if(dut.bmp_data_valid!==(present && position>=offset && position<length))
   $fatal(1,"BMP bounds changed position=%d offset=%d length=%d",position,offset,length);
  checks=checks+1;@(posedge clk);#1;if(present)position=position+1;
 end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(i=0;i<8;i=i+1)for(gap=0;gap<3;gap=gap+1)begin
  @(negedge clk);forced_state=3;valid=0;position=0;
  case(i)
   0:begin offset=54;length=118;end
   1:begin offset=255;length=512;end
   2:begin offset=256;length=1024;end
   3:begin offset=511;length=2049;end
   4:begin offset=512;length=8192;end
   5:begin offset=65536;length=4194304;end
   6:begin offset=8388500;length=8388608;end
   7:begin offset=8388000;length=8388607;end
  endcase
  repeat(4)@(negedge clk);forced_state=4;position=offset-3;
  for(j=0;j<10;j=j+1)begin step(1);repeat(gap)step(0);end
  // Skip only interior payload positions, where both boundary flags hold.
  @(negedge clk);position=length-3;
  for(j=0;j<10;j=j+1)begin step(1);repeat(gap)step(0);end
 end
 $display("PASS BMP boundary flags: %d observations, gaps, 54-byte header and full 8MiB upper bound",checks);$finish;
end
initial begin #1000000;$fatal(1,"bounds timeout");end
endmodule
