`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,start=0,byte_valid=0,block_end=0;
reg [7:0] byte_data=0;wire ready,done,req,write_req,pixel_valid;wire [3:0] error;
wire [23:0] pixel;wire [31:0] sector;integer bytes,gap,overlap,i,j,cases=0;
always #5 clk=~clk;
photo_dlt_reader dut(.clk(clk),.rst(rst),.start(start),.start_sector(32'd100),
 .ready(ready),.done(done),.error(error),.write_req(write_req),.write_ack(1'b0),.full(1'b0),
 .pixel_valid(pixel_valid),.pixel(pixel),.req(req),.sector(sector),
 .byte_valid(byte_valid),.byte_data(byte_data),.block_end(block_end));
task run;
 input integer count,spacing,same_edge;
 begin
  @(negedge clk);rst=1;byte_valid=0;block_end=0;start=0;
  repeat(4)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
  for(i=0;i<count;i=i+1)begin
   @(negedge clk);byte_valid=1;byte_data=$random;
   block_end=same_edge && i==count-1;
   @(negedge clk);byte_valid=0;
   if(same_edge && i==count-1)block_end=0;
   repeat(spacing)@(negedge clk);
  end
  if(!same_edge || count==0)begin block_end=1;@(negedge clk);block_end=0;end
  repeat(12)@(negedge clk);
  if(!ready || error==0)$fatal(1,"bad sector accepted count=%0d",count);
  cases=cases+1;
 end
endtask
initial begin
 for(gap=0;gap<3;gap=gap+1)for(overlap=0;overlap<2;overlap=overlap+1)begin
  run(0,gap,overlap);run(1,gap,overlap);run(31,gap,overlap);
  run(511,gap,overlap);run(512,gap,overlap);run(513,gap,overlap);
 end
 $display("PASS %0d malformed/short/long DLT sectors, gaps and final-valid/end overlap, cycle-equivalent to f6",cases);$finish;
end
endmodule
