`timescale 1ns/1ps
// Elaborate next to either real reader bench and compare every public output
// and the original state/count sequence with the immutable 5.3 reader.
module equivalence;
wire ready,done,write_req,pixel_valid,req;wire [3:0] error;
wire [23:0] pixel;wire [31:0] sector;
reference_photo_dlt_reader golden(.clk(tb.dut.clk),.rst(tb.dut.rst),
 .start(tb.dut.start),.start_sector(tb.dut.start_sector),.ready(ready),.done(done),.error(error),
 .write_req(write_req),.write_ack(tb.dut.write_ack),.full(tb.dut.full),.pixel_valid(pixel_valid),.pixel(pixel),
 .req(req),.sector(sector),.byte_valid(tb.dut.byte_valid),.byte_data(tb.dut.byte_data),.block_end(tb.dut.block_end));
always @(negedge tb.dut.clk)if(!tb.dut.rst)begin
 if({ready,done,error,write_req,pixel_valid,pixel,req,sector}!==
    {tb.dut.ready,tb.dut.done,tb.dut.error,tb.dut.write_req,tb.dut.pixel_valid,tb.dut.pixel,tb.dut.req,tb.dut.sector})
  $fatal(1,"DLT output changed at state %0d count %0d",tb.dut.state,tb.dut.count);
 if(golden.state!==tb.dut.state || golden.count!==tb.dut.count)
  $fatal(1,"DLT state/count latency changed");
end
endmodule
