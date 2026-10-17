`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,load=0,abort_load=0,ack=0;
wire ready,write_req,request,pixel_valid;wire[31:0] sector;wire[23:0] pixel;
reg[7:0] byte_in=0;reg valid=0,sector_end=0;
bmp_read #(.NATIVE_720_ONLY(1)) dut(.clk(clk),.rst(rst),.op_abort(abort_load),.ready(ready),
 .scan_start(1'b0),.scan_stop(1'b0),.scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd5),
 .load_start(load),.load_sector(32'd0),.sd_init_done(1'b1),.bmp_width(16'd1280),.bmp_height(16'd720),
 .write_req(write_req),.write_req_ack(ack),.sd_sec_read(request),.sd_sec_read_addr(sector),
 .sd_sec_read_data(byte_in),.sd_sec_read_data_valid(valid),.sd_sec_read_end(sector_end),
 .bmp_data_wr_en(pixel_valid),.bmp_data(pixel));
reg[7:0] header[0:63];integer length,ack_age=0,received=0,checked=0,i,j,offset,base,pix,component;
function[23:0] color;input integer n;reg[7:0] r,g,b;begin r=n>>8;g=n*7;b=n^(n>>8);color={r,g,b};end endfunction
// Explicit byte extraction avoids unsized concatenation in the test pattern.
function[7:0] pixel_byte;input integer n,c;reg[23:0] rgb;begin rgb=color(n);pixel_byte=rgb>>(c*8);end endfunction
task le32;input integer pos,value;integer k;begin for(k=0;k<4;k=k+1)header[pos+k]=(value>>(8*k))&255;end endtask
task setup_header;input integer w,h;begin
 for(j=0;j<64;j=j+1)header[j]=0;
 length=54+w*h*3;header[0]="B";header[1]="M";le32(2,length);le32(10,54);le32(14,40);
 le32(18,w);le32(22,h);header[26]=1;header[28]=24;
end endtask
always @(posedge clk)begin
 if(write_req)begin ack_age<=ack_age+1;ack<=ack_age>=5;end else begin ack_age<=0;ack<=0;end
 if(pixel_valid&&!rst&&!abort_load)begin
  if(pixel!==color(received))$fatal(1,"native pixel%0d actual%h expected%h",received,pixel,color(received));
  received=received+1;checked=checked+1;
 end
end
initial begin
 forever begin
  wait(request&&!rst);base=sector*512;
  for(i=0;i<512;i=i+1)begin
   @(negedge clk);offset=base+i;
   if(offset<54)byte_in=header[offset];
   else if(offset<length)begin pix=(offset-54)/3;component=(offset-54)%3;byte_in=pixel_byte(pix,component);end
   else byte_in=0;
   valid=1;
   if(i%17==0)begin @(negedge clk);valid=0;end
  end
  @(negedge clk);valid=0;sector_end=1;
  @(negedge clk);sector_end=0;
  wait(!request);repeat(3)@(negedge clk);
 end
end
task start_and_wait;begin
 @(negedge clk);load=1;@(negedge clk);load=0;wait(!ready);wait(ready);repeat(8)@(negedge clk);
end endtask
initial begin
 setup_header(640,480);repeat(8)@(negedge clk);rst=0;
 start_and_wait;
 if(received!=0)$fatal(1,"unsupported geometry was accepted");
 setup_header(1280,720);header[28]=16;start_and_wait;
 if(received!=0)$fatal(1,"unsupported bit depth was accepted");
 setup_header(1280,720);start_and_wait;
 if(received!=921600)$fatal(1,"native frame length %0d",received);
 $display("PASS native BMP stream: %0d exact pixels with sector/byte gaps, delayed ACK, rejected non-720p and non-24-bit headers",checked);$finish;
end
initial begin #80000000;$fatal(1,"native decoder timeout state%0d pixels%0d",dut.state,received);end
endmodule
