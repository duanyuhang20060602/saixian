`timescale 1ns/1ps
module tb_award_headers;
reg clk=0;always #5 clk=~clk;
reg rst=1,scan=0,valid=0,last=0;reg [7:0] data=0;
wire req,done,found;wire [15:0] width,height;integer mode=0,i;
reg [7:0] header[0:511];reg seen=0;
bmp_read dut(.high_color(1'b0),.clk(clk),.rst(rst),.op_abort(1'b0),.scan_start(scan),.scan_stop(1'b0),.scan_resume(1'b0),
 .scan_start_sector(32'd0),.scan_max_sector(32'd0),.scan_target_count(3'd1),.scan_done(done),
 .scan_found_valid(found),.scan_found_width(width),.scan_found_height(height),.load_start(1'b0),.load_sector(32'd0),
 .sd_init_done(1'b1),.bmp_width(16'd1280),.bmp_height(16'd720),.write_req_ack(1'b0),
 .sd_sec_read(req),.sd_sec_read_data(data),.sd_sec_read_data_valid(valid),.sd_sec_read_end(last));
always @(negedge clk)if(found)begin
 seen=1;
 if(width[15] !== 1'b0)$fatal(1,"false award type case=%0d width=%h",mode,width);
end
initial begin
 for(i=0;i<512;i=i+1)header[i]=0;
 header[0]="B";header[1]="M";header[2]=8'h36;header[3]=8'h30;header[4]=8'h2a;
 header[10]=54;header[14]=40;header[18]=0;header[19]=5;header[22]=8'hd0;header[23]=2;
 header[26]=1;header[28]=24;
 for(mode=0;mode<7;mode=mode+1)begin
  rst=1;scan=0;seen=0;repeat(4)@(negedge clk);rst=0;scan=1;@(negedge clk);scan=0;
  wait(req);
  for(i=0;i<512;i=i+1)begin
   @(negedge clk);data=header[i];valid=1;
   if(i>=6 && i<=9)case(i)
    6:data="S";7:data="X";8:data="A";9:data="W";
   endcase
   if(mode>=1 && mode<=4 && i==mode+5)data=0;
   if(mode==5 && i==18)data=1; // tagged 1281-wide photo: no effect interpretation
   if(mode==6 && i==22)data=8'hd1;
  end
  @(negedge clk);valid=0;last=1;@(negedge clk);last=0;
  wait(done);repeat(4)@(negedge clk);
  if(!seen)$fatal(1,"valid photo was not discovered case=%0d",mode);
 end
 $display("PASS every BMP remains a photo: old SXAW magic, altered magic and non-native geometry never enable award");$finish;
end
initial begin #1000000;$fatal(1,"header test timeout");end
endmodule
