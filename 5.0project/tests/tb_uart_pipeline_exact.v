`timescale 1ns/1ps
module tb;
parameter DIV=1,PULSE=0;
reg clk=0,rst=1,send=0,noise=0;always #5 clk=~clk;
reg [159:0] message=0;wire at,bt,ab,bb,ag,bg,ae,be;wire[159:0] am,bm;
wire rx=at^noise;
photo_uart #(.CLK_HZ(DIV*115200),.BAUD(115200),.PULSE_PAYLOAD(PULSE)) a(clk,rst,rx,at,send,message,ab,ag,am,ae);
photo_uart_before #(.CLK_HZ(DIV*115200),.BAUD(115200),.PULSE_PAYLOAD(PULSE)) b(clk,rst,rx,bt,send,message,bb,bg,bm,be);
integer i,j,n=0;reg[31:0] rng=32'h123456ab;
always @(negedge clk)if(!rst)begin
 if({at,ab,ag,ae,am,a.tx_crc}!=={bt,bb,bg,be,bm,b.tx_crc})$fatal(1,"changed at cycle %0d DIV=%0d PULSE=%0d",n,DIV,PULSE);
 n=n+1;
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<24;i=i+1)begin
  message={$random,$random,$random,$random,$random};send=1;@(negedge clk);send=0;
  for(j=0;j<242*DIV;j=j+1)begin
   @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   // Busy sends, changing source data, line corruption, and reset mid-frame.
   send=(j%103==77);message=message+1'b1;
   noise=(i%3==1 && j>80*DIV && j<81*DIV);
   rst=(i%5==4 && j==130*DIV);
  end
  send=0;noise=0;rst=0;repeat(100*DIV)@(negedge clk);
 end
 $display("PASS UART exact every cycle: DIV=%0d PULSE=%0d clocks=%0d",DIV,PULSE,n);$finish;
end
endmodule
