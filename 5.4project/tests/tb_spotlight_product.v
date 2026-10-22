`timescale 1ns/1ps
module tb_spotlight_product;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [7:0] source=0,top=0;reg [2:0] fraction=0;
integer a,b,f,checks=0;
photo_spotlight_player dut(.mem_clk(clk),.mem_rst(rst),.enable(1'b0),.base(21'd0),.stream_ack(1'b0),.data(32'd0),.data_valid(1'b0),
 .video_clk(clk),.video_rst(rst),.display_valid(1'b0),.pause(1'b0),.rgb_in(24'd0),.de_in(1'b0),.vs_in(1'b0));
initial begin
 force dut.source_byte=source;force dut.top_selected=top;force dut.line_fy=fraction;
 repeat(3)@(negedge clk);rst=0;
 for(a=0;a<256;a=a+1)for(b=0;b<256;b=b+1)for(f=0;f<8;f=f+1)begin
  @(negedge clk);source=a;top=b;fraction=f;
  @(posedge clk);#1;
  if($signed(dut.vertical_product)!==(a-b)*f || dut.vertical_base!==b*8)
   $fatal(1,"signed interpolation mismatch source=%d top=%d fraction=%d got=%d",a,b,f,$signed(dut.vertical_product));
  checks=checks+1;
 end
 @(negedge clk);rst=1;@(posedge clk);#1;if(dut.vertical_product!==0)$fatal(1,"reset product");
 $display("PASS exact registered interpolation vs original signed multiply: %0d cases, all source/top bytes and fractions, reset and unchanged latency",checks);$finish;
end
endmodule
