`timescale 1ns/1ps
module tb_cache_crc;
reg clk=0,rst=1;
integer mode,i,n;
reg [31:0] ram[0:511],data_pipe[0:7];
reg [7:0] valid_pipe=0;
wire rd,wr,ready;
wire [20:0] ra,wa;
wire [31:0] wd,up_data;
wire [3:0] error;
reg [31:0] payload_crc,crc;
always #5 clk=~clk;
function [31:0] value;input integer index;begin value=32'ha5e1923f^(index*32'h12345);end endfunction
function [31:0] crc_word;
input [31:0] old,word;reg [31:0] c;integer k;
begin c=old^word;for(k=0;k<32;k=k+1)c=c[0] ? (c>>1)^32'hedb88320 : c>>1;crc_word=c;end
endfunction
assign up_data=value(dut.upload_written)^((mode==2 && dut.upload_written==137) ? 32'd1 : 32'd0);
delta_memory #(.VERIFY_CACHE(1),.RUN_BUS_TEST(0)) dut(
 .clk(clk),.rst(rst),.init(1'b1),.refreshing(1'b0),.busy(1'b0),
 .app_rd(rd),.rd_addr(ra),.rd_valid(valid_pipe[7]),.rd_data(data_pipe[7]),
 .app_wr(wr),.wr_addr(wa),.wr_data(wd),.upload_done(1'b1),.file_words(21'd512),
 .up_empty(dut.upload_written==512),.up_count(9'd64),.up_data(up_data),.cache_ready(ready),
 .frame_toggle(1'b0),.display_valid(1'b0),.active_slot(1'b0),.video_count(9'd0),
 .stream_start(1'b0),.stream_offset(21'd0),.stream_words(21'd0),.cmd_count(9'd0),
 .patch_valid(1'b0),.patch_addr(21'd0),.patch_data(32'd0),.payload_crc(payload_crc),.error(error));
always @(posedge clk)begin
 if(rst)valid_pipe<=0;
 else begin
  valid_pipe<={valid_pipe[6:0],rd};
  if(rd)data_pipe[0]<=ram[ra-230400]^((mode==1 && ra==230537) ? 32'd1 : 32'd0);
  for(n=1;n<8;n=n+1)data_pipe[n]<=data_pipe[n-1];
  if(wr)begin
   if(wa<230400 || wa>=230912)$fatal(1,"fixed-pattern test unexpectedly wrote header");
   ram[wa-230400]<=wd;
  end
 end
end
initial begin
crc=32'hffffffff;for(i=128;i<512;i=i+1)crc=crc_word(crc,value(i));payload_crc=crc^32'hffffffff;
for(mode=0;mode<4;mode=mode+1)begin
 rst=1;repeat(4)@(negedge clk);rst=0;
 wait(ready || error!=0);@(negedge clk);
 if(mode==1 && (ready || error!=9))$fatal(1,"readback corruption escaped cache CRC");
 if(mode==2 && (ready || error!=10))$fatal(1,"upload corruption escaped cache CRC");
 if((mode==0 || mode==3) && (!ready || error!=0))$fatal(1,"valid upload/reentry failed");
end
$display("PASS compact cache verification: actual payload CRC before/after SDRAM, corrupt upload E10, corrupt read E9, recovery, no fixed-pattern writes");$finish;
end
initial begin #1000000;$fatal(1,"cache CRC timeout");end
endmodule
