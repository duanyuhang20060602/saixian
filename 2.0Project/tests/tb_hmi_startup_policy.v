`timescale 1ns/1ps
module tb_hmi_startup_policy;
reg clk=0;always #5 clk=~clk;
reg rst=1,initializing=1;reg [2:0] error_code=0;
wire uart_tx,command_sent_pulse;
saixian_hmi_status_tx #(.CLK_FREQ_HZ(2000),.BAUD_RATE(200)) dut(
 .clk(clk),.rst(rst),.image_count(3'd5),.audio_found(1'b1),
 .error_code(error_code),.initializing(initializing),.uart_tx(uart_tx),.command_sent_pulse(command_sent_pulse));
reg [7:0] bytes[0:31],received;integer n=0,pages=0;
reg [15:0] expected;
initial begin repeat(4) @(negedge clk);rst=0;end
initial begin
 wait(!rst);
 forever begin
  @(negedge uart_tx);repeat(15) @(posedge clk);#1;
  for(integer b=0;b<8;b=b+1) begin
   received[b]=uart_tx;if(b<7) begin repeat(10) @(posedge clk);#1;end
  end
  repeat(10) @(posedge clk);#1;
  if(uart_tx!==1) $fatal(1,"UART stop bit");
  bytes[n]=received;n=n+1;
  if(n>=3 && bytes[n-1]==255 && bytes[n-2]==255 && bytes[n-3]==255) begin
   if(bytes[2]==8'h31) begin
    case(pages)0:expected="IN";1:expected="OK";2:expected="E2";default:expected="E1";endcase
    if(n!=17 || {bytes[11],bytes[12]}!==expected || bytes[13]!=8'h22)
     $fatal(1,"Status policy text changed page %0d",pages);
    pages=pages+1;
    @(negedge clk);
    case(pages)
     1:initializing=0;
     2:begin initializing=1;error_code=2;end
     3:error_code=1;
     4:begin $display("PASS UART status IN/OK/E2/E1, existing component IDs and command framing");$finish;end
    endcase
   end else if(n!=15 || bytes[10]!=(bytes[2]==8'h37 ? 8'h35 : 8'h31))
    $fatal(1,"Picture/music fields changed");
   n=0;
  end
 end
end
initial begin #1000000;$fatal(1,"UART timeout");end
endmodule
