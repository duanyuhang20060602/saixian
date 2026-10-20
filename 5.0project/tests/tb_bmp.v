`timescale 1ns/1ps
module tb_bmp;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,scan=0,load=0,init=0;wire ready,scan_done,found,req,sec_req,ov,fault;
 wire [31:0] sec_addr,found_sector;wire [23:0] rgb;
 reg [7:0] byte_data=0;reg byte_valid=0,sec_end=0;
 bmp_read dut(.clk(clk),.rst(rst),.op_abort(1'b0),.ready(ready),
  .scan_start(scan),.scan_stop(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd8),.scan_target_count(3'd1),
  .scan_done(scan_done),.scan_found_valid(found),.scan_found_sector(found_sector),.scan_found_total(),
  .scan_found_width(),.scan_found_height(),.scan_found_sprint(),.audio_found_valid(),.audio_found_index(),
  .audio_found_sector(),.audio_found_bytes(),.load_start(load),.load_sector(32'd0),.sd_init_done(init),
  .state_code(),.bmp_width(16'd1280),.bmp_height(16'd720),.write_req(req),.write_req_ack(req),
  .sd_sec_read(sec_req),.sd_sec_read_addr(sec_addr),.sd_sec_read_data(byte_data),
  .sd_sec_read_data_valid(byte_valid),.sd_sec_read_end(sec_end),.bmp_data_wr_en(ov),.bmp_data(rgb),.scaler_fault_o(fault));
 function [23:0] picture;
  input integer x,y;reg [7:0] r,g,b;
  begin r=x;g=y;b=x^y;picture={r,g,b};end
 endfunction
 function [7:0] file_byte;
  input integer address;integer offset,row,col,index;reg [23:0] p;
  begin
   file_byte=0;
   if(address<54)case(address)
    0:file_byte=8'h42;1:file_byte=8'h4d;
    2:file_byte=2764854&255;3:file_byte=(2764854>>8)&255;4:file_byte=(2764854>>16)&255;
    10:file_byte=54;14:file_byte=40;18:file_byte=8'h00;19:file_byte=8'h05;22:file_byte=8'hd0;
    23:file_byte=8'h02;26:file_byte=1;28:file_byte=24;
    default:file_byte=0;
   endcase
   else if(address<2764854)begin
    offset=address-54;row=offset/3840;col=offset%3840;index=col/3;
    p=picture(index,719-row);
    if(col<3840)case(col%3)0:file_byte=p[7:0];1:file_byte=p[15:8];2:file_byte=p[23:16];endcase
   end
  end
 endfunction
 integer i,sector,count=0;reg found_seen=0;
 always @(negedge clk)begin
  if(found)found_seen=1;
  if(fault)begin $fatal(1,"FAIL native BMP scaler fault");end
  if(ov)begin
   if(rgb!==picture(count%1280,719-count/1280))begin $fatal(1,"FAIL BMP byte/padding pixel=%0d got=%h",count,rgb);end
   count=count+1;
  end
 end
 initial forever begin
  wait(sec_req);sector=sec_addr;
  for(i=0;i<512;i=i+1)begin @(negedge clk);byte_data=file_byte(sector*512+i);byte_valid=1;end
  @(negedge clk);byte_valid=0;sec_end=1;
  @(negedge clk);sec_end=0;wait(!sec_req);
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;init=1;scan=1;@(negedge clk);scan=0;
  wait(scan_done);wait(ready);repeat(2)@(negedge clk);
  if(!found_seen)begin $fatal(1,"FAIL native BMP scan");end
  load=1;@(negedge clk);load=0;
  wait(count==921600);wait(ready);repeat(10)@(negedge clk);
  if(count!=921600)begin $fatal(1,"FAIL native BMP extra pixels");end
  $display("PASS native BMP scan/header/BGR/row padding 1280x720 pixels=%0d",count);$finish;
 end
 initial begin #40000000;$fatal(1,"FAIL BMP timeout count=%0d state=%0d sector=%0d",count,dut.state,sec_addr);end
endmodule
