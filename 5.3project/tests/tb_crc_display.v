`timescale 1ns/1ps
module tb_crc_display;
reg clk=0;always #5 clk=~clk;reg rst=1;reg [2:0] page=0;reg [15:0] crc=16'habcd;
wire [5:0] sel;wire [7:0] segments;
photo_status #(.CLK_HZ(6000)) s(.clk(clk),.rst(rst),.status(4'd9),.error(4'd4),.state(4'd12),
 .image(3'd0),.count(3'd6),.diagnostic_page(page),.diagnostic_crc(crc),.seg_sel(sel),.seg_data(segments));
integer i;
initial begin
 repeat(3)@(negedge clk);rst=0;repeat(12)@(negedge clk);
 if(s.digits!=24'h604129)$fatal(1,"normal status order");
 for(i=1;i<=4;i=i+1)begin
  page=i;repeat(12)@(negedge clk);
  if(s.digits!={20'hcdcba,1'b0,page})$fatal(1,"CRC page/nibble order");
 end
 page=0;repeat(12)@(negedge clk);
 if(s.digits!=24'h604129)$fatal(1,"return to status");
 $display("PASS status and four CRC pages, human reading order page/ABCD/C");$finish;
end
endmodule
