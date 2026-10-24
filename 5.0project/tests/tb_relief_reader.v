`timescale 1ns/1ps
module tb #(parameter FILE_WORDS=700000);
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,ack=0,byte_valid=0,block_end=0;reg [7:0] byte_data=0;
reg [31:0] file_words[0:FILE_WORDS-1],expected[0:691199];
wire ready,done,write_req,pixel_valid,req,word_valid,aligned;wire [3:0] error;
wire [23:0] pixel;wire [31:0] sector,word_data;integer n=0,j,checks=0,cycles=0;reg full=0;
photo_dlt_reader dut(.clk(clk),.rst(rst),.start(start),.start_sector(32'd100),.ready(ready),.done(done),.error(error),
 .write_req(write_req),.write_ack(ack),.full(full),.pixel_valid(pixel_valid),.pixel(pixel),
 .req(req),.sector(sector),.byte_valid(byte_valid),.byte_data(byte_data),.block_end(block_end));
photo_color_pack packing(.clk(clk),.rst(rst),.clear(write_req),.valid(pixel_valid),.rgb(pixel),
 .word_valid(word_valid),.word_data(word_data),.aligned(aligned));
always @(posedge clk)begin
 cycles<=cycles+1;ack<=write_req;
 if(error)$fatal(1,"DLT reader error %0d",error);
 if(word_valid)begin
  if(checks>=691200 || word_data!==expected[checks])$fatal(1,"DLT word mismatch %0d actual=%h expected=%h",checks,word_data,expected[checks]);
  checks=checks+1;
 end
end
always @(negedge clk)full=!rst && cycles%127<11;
initial begin
 $readmemh("award_file.hex",file_words);$readmemh("award_expected.hex",expected);
 repeat(8)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
 while(!done)begin
  wait(req || done);
  if(!done)begin
   n=(sector-100)*512;
   for(j=0;j<512;j=j+1)begin
    @(negedge clk);byte_valid=1;byte_data=file_words[(n+j)/4]>>(((n+j)%4)*8);
   end
   @(negedge clk);byte_valid=0;block_end=1;
   @(negedge clk);block_end=0;
   wait(!req);repeat(3)@(negedge clk);
  end
 end
 repeat(8)@(negedge clk);
 if(checks!=691200 || !aligned)$fatal(1,"incomplete DLT transport %0d",checks);
 $display("PASS SXDLT TF decoding and RGB565 packing: 691200 exact words including plate, opaque tail and full backpressure");$finish;
end
initial begin #500000000;$fatal(1,"reader timeout state=%0d words=%0d",dut.state,checks);end
endmodule
