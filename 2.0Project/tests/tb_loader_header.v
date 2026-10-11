`timescale 1ns/1ps
module tb_loader_header;
reg clk=0,rst=1,valid=0;
reg [7:0] data;
reg [7:0] original[0:43];
reg [1023:0] filename;
integer i,j;
always #5 clk=~clk;
delta_loader dut(.clk(clk),.rst(rst),.sd_init(1'b1),.valid(valid),.data(data),.block_end(1'b0),.fifo_full(1'b0));
baseline_delta_loader baseline(.clk(clk),.rst(rst),.sd_init(1'b1),.valid(valid),.data(data),.block_end(1'b0),.fifo_full(1'b0));
initial begin
if(!$value$plusargs("HEADER=%s",filename))$fatal(1,"HEADER missing");
$readmemh(filename,original);
for(i=0;i<1000;i=i+1)begin
 rst=1;valid=0;repeat(3)@(negedge clk);rst=0;
 wait(dut.state==2);@(negedge clk);
 for(j=0;j<44;j=j+1)begin
  valid=1;data=i==0 ? original[j] : (i<353 ? original[j]^(j==((i-1)/8) ? (1<<((i-1)%8)) : 0) : $random);
  @(negedge clk);
 end
 valid=0;repeat(3)@(negedge clk);
 if(dut.header!==baseline.header || dut.header_checks!==baseline.header_checks)
  $fatal(1,"header packing mismatch case %d",i);
 if(i==0 && dut.header_checks!==7'h7f)$fatal(1,"actual DLT header rejected");
end
$display("PASS serial header packing: actual DLT, all 352 single-bit corruptions, random headers; exact bytes/checks");$finish;
end
endmodule
