`timescale 1ns/1ps
module tb_hmi_relay_recovery;
reg clk=0;always #5 clk=~clk;
reg rst=1;reg [31:0] session=42;reg pb=0,wv=0,commit=0;reg [1:0] wi=0;reg [31:0] wd=0;
wire ack,reset_request,uart;wire [7:0] token;
photo_hmi_relay_a #(.CLK_HZ(1000000),.BAUD(100000),.CHUNK_BYTES(8)) dut(.clk(clk),.rst(rst),.session(session),.packet_begin(pb),.word_valid(wv),
 .word_index(wi),.word_data(wd),.commit(commit),.ack_valid(ack),.ack_token(token),.reset_request(reset_request),.uart_tx(uart));
reg [7:0] expected[0:2047];integer wp=0,rp=0,k,n;reg [7:0] byte_value;
task expect_byte;input [7:0] b;begin expected[wp]=b;wp=wp+1;end endtask
task flush;begin expect_byte(255);expect_byte(255);expect_byte(255);end endtask
always begin
 @(negedge uart);if(!rst)begin
  repeat(15)@(negedge clk);
  for(k=0;k<8;k=k+1)begin byte_value[k]=uart;repeat(10)@(negedge clk);end
  if(!rst)begin
   if(!uart || rp>=wp || byte_value!==expected[rp])$fatal(1,"UART replay/order at %d got=%h expected=%h",rp,byte_value,expected[rp]);rp=rp+1;
  end
 end
end
task packet;
 input [7:0] seq;input [3:0] count;input first,good;input [95:0] bytes;
 begin
  @(negedge clk);pb=1;@(negedge clk);pb=0;
  wv=1;wi=0;wd={8'h48,seq,count,first,11'd0};@(negedge clk);
  wi=1;wd=bytes[95:64];@(negedge clk);wi=2;wd=bytes[63:32];@(negedge clk);wi=3;wd=bytes[31:0];@(negedge clk);wv=0;
  commit=good;@(negedge clk);commit=0;repeat(3)@(negedge clk);
 end
endtask
task idle;begin wait(!dut.active && dut.remaining==0 && dut.flush==0);repeat(4)@(negedge clk);end endtask
initial begin
 flush();repeat(20)@(negedge clk);rst=0;idle();
 expect_byte("a");expect_byte("b");expect_byte("c");expect_byte("d");packet(0,4,1,1,{"abcd",64'd0});
 // A complete new candidate during UART transmission cannot overwrite bytes.
 packet(1,3,0,1,{"BAD",72'd0});if(token!=0)$fatal(1,"busy chunk ACK");idle();
 packet(0,4,1,1,{"abcd",64'd0});packet(1,4,0,0,{"BAD!",64'd0});packet(2,4,0,1,{"BAD!",64'd0});
 repeat(200)@(negedge clk);if(token!=0 || rp!=wp)$fatal(1,"duplicate/bad/out-of-order accepted");
 expect_byte("w");expect_byte("x");expect_byte("y");expect_byte("z");packet(1,4,0,1,{"wxyz",64'd0});idle();
 // Session replacement preserves an active byte and terminates the old command.
 expect_byte("1");packet(2,6,0,1,{"123456",48'd0});wait(dut.active && dut.bit_index==4);
 flush();@(negedge clk);session=43;packet(3,3,0,1,{"BAD",72'd0});idle();
 if(ack || !reset_request)$fatal(1,"session did not reset ACK");
 packet(0,3,0,1,{"BAD",72'd0});if(ack)$fatal(1,"first chunk lacks reset marker");
 expect_byte("N");expect_byte("E");expect_byte("W");packet(0,3,1,1,{"NEW",72'd0});idle();
 // 8-bit token rollover remains ordered with at most one in-flight chunk.
 for(n=1;n<=256;n=n+1)begin expect_byte(n[7:0]);packet(n[7:0],1,0,1,{n[7:0],88'd0});idle();end
 if(token!=0 || rp!=wp)$fatal(1,"token rollover");
 @(negedge clk);rst=1;flush();repeat(200)@(negedge clk);rst=0;idle();
 expect_byte("R");packet(0,1,1,1,{8'h52,88'd0});idle();
 if(rp!=wp || !ack || reset_request)$fatal(1,"reboot recovery");
 $display("PASS UART relay: busy backpressure, duplicate/bad/out-of-order rejection, session replacement during byte, 256-token rollover, same-session A reboot and terminator flush");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
