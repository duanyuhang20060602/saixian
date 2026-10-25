`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,valid=0,ending=0;always #5 clk=~clk;
reg [7:0] data=0,records[0:1023];wire ready;wire [4:0] length;
wire [6:0] address;wire [31:0] word;integer i;
photo_sd_title_store store(clk,rst,valid,data,ending,ready,length,address,word);
photo_control_b #(.CLK_HZ(921600),.TITLE_SD(1)) b(.clk(clk),.rst(rst),.uart_rx(1'b1),
 .title_ready(ready),.title_length(length),.title_data(word),.title_address(address),
 .image_count(3'd1),.award_available(1'b0),.award_scan_complete(1'b1),.relief_available(1'b0),
 .media_ready(1'b0),.media_slot(2'd0),.media_error(4'd0),.media_source_width(16'd1280),.media_source_height(16'd720),.tx_done(1'b0),.tx_crc(32'd0));
initial begin
 $readmemh("first_word_records.hex",records);
 repeat(5)@(negedge clk);rst=0;b.state=2;b.session=1;b.announced_count=1;
 for(i=0;i<1024;i=i+1)begin
  @(negedge clk);valid=1;data=records[i];
  if(i%512==511)begin @(negedge clk);valid=0;ending=1;@(negedge clk);ending=0;end
 end
 wait(b.send && b.message[159:152]==33);
 if(b.message[119:112]!=0 || b.message[111:104]!=16 || b.message[103:72]!==32'h13579bdf)
  $fatal(1,"first ready-to-send boundary captured stale title RAM data: %h",b.message[103:72]);
 $display("PASS nonzero first word on the first ready-to-send edge; actual SD decoder, dual-port RAM and B UART scheduler");$finish;
end
initial begin #100000;$fatal(1,"first word timeout");end
endmodule
