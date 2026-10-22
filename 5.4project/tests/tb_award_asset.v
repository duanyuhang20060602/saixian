`timescale 1ns/1ps
// Load the actual released BMP through the production header/parser/scaler
// and compare every pixel and both RGB565/RGB888 packing paths.
module tb_award_asset;
reg clk=0;always #5 clk=~clk;
reg rst=1,scan=0,load=0;wire ready,scan_done,found,req,sec_req,ov,fault;
wire [31:0] sec_addr;wire [15:0] found_width,found_height;wire [23:0] rgb;
reg [7:0] bytes[0:2765311];reg [23:0] expected[0:921599];
reg [7:0] data=0;reg valid=0,sec_end=0;
bmp_read dut(.clk(clk),.rst(rst),.op_abort(1'b0),.ready(ready),
 .scan_start(scan),.scan_stop(1'b0),.scan_resume(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd1),
 .scan_done(scan_done),.scan_found_valid(found),.scan_found_width(found_width),.scan_found_height(found_height),
 .load_start(load),.load_sector(32'd0),.sd_init_done(1'b1),.bmp_width(16'd1280),.bmp_height(16'd720),
 .write_req(req),.write_req_ack(req),.sd_sec_read(sec_req),.sd_sec_read_addr(sec_addr),
 .sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(sec_end),
 .bmp_data_wr_en(ov),.bmp_data(rgb),.scaler_fault_o(fault));
wire w565,w888,a565,a888;wire [31:0] d565,d888;
photo_color_pack pack565(clk,rst,req,1'b0,ov,rgb,w565,d565,a565);
photo_color_pack pack888(clk,rst,req,1'b1,ov,rgb,w888,d888,a888);
function [15:0] to565;input [23:0] v;begin to565={v[23:19],v[15:10],v[7:3]};end endfunction
integer count=0,c565=0,c888=0,sector,i,j;reg found_seen=0;reg [31:0] target;
always @(negedge clk)begin
 if(found)begin
  found_seen=1;
  if(found_width!==16'h8500 || found_height!==720)$fatal(1,"award metadata detection");
 end
 if(fault)$fatal(1,"native asset scaler fault");
 if(ov)begin
  if(rgb!==expected[count])$fatal(1,"asset pixel/tag mismatch %0d got=%h expected=%h",count,rgb,expected[count]);
  count=count+1;
 end
 if(w565)begin
  target={to565(expected[c565*2]),to565(expected[c565*2+1])};
  if(d565!==target)$fatal(1,"RGB565 packing/tag mismatch %0d",c565);
  c565=c565+1;
 end
 if(w888)begin
  j=(c888/3)*4;
  case(c888%3)
   0:target={expected[j],expected[j+1][23:16]};
   1:target={expected[j+1][15:0],expected[j+2][23:8]};
   2:target={expected[j+2][7:0],expected[j+3]};
  endcase
  if(d888!==target)$fatal(1,"RGB888 packing/tag mismatch %0d",c888);
  c888=c888+1;
 end
end
initial forever begin
 wait(sec_req);sector=sec_addr;
 for(i=0;i<512;i=i+1)begin @(negedge clk);data=bytes[sector*512+i];valid=1;end
 @(negedge clk);valid=0;sec_end=1;@(negedge clk);sec_end=0;wait(!sec_req);
end
initial begin
 $readmemh("tests/results/award_bytes.hex",bytes);
 $readmemh("tests/results/award_pixels.hex",expected);
 repeat(5)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
 wait(scan_done);wait(ready);repeat(2)@(negedge clk);
 if(!found_seen)$fatal(1,"award not discovered");
 load=1;@(negedge clk);load=0;
 wait(count==921600);wait(ready);repeat(10)@(negedge clk);
 if(c565!=460800 || c888!=691200 || !a565 || !a888)$fatal(1,"packing length or incomplete tail");
 $display("PASS actual AWARD720.BMP scan, metadata, all 921600 exact pixels/tags, RGB565 460800 words and RGB888 691200 words");$finish;
end
initial begin #50000000;$fatal(1,"award BMP timeout %0d",count);end
endmodule
