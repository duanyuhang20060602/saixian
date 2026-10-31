`timescale 1ns/1ps
module tb;
parameter BAUD=230400;
reg ca=0,cb=0,rst=1,sa=0,sb=0;always #6.666667 ca=~ca;always #5.001 cb=~cb;
wire at,bt,ab,bb,ag,bg,ae,be;reg [159:0] am=0,bm=0;wire[159:0] ar,br;
photo_uart #(.CLK_HZ(75000000),.BAUD(BAUD)) a(ca,rst,bt,at,sa,am,ab,ag,ar,ae);
photo_uart #(.CLK_HZ(100000000),.BAUD(BAUD)) b(cb,rst,at,bt,sb,bm,bb,bg,br,be);
integer i,na=0,nb=0;
always @(posedge ca)if(!rst)begin if(ae)$fatal(1,"A rejected CRC/framing");if(ag)begin if(ar!==bm)$fatal(1,"A payload mismatch");na=na+1;end end
always @(posedge cb)if(!rst)begin if(be)$fatal(1,"B rejected CRC/framing");if(bg)begin if(br!==am)$fatal(1,"B payload mismatch");nb=nb+1;end end
initial begin
 #103;rst=0;
 for(i=0;i<32;i=i+1)begin
  am={$random,$random,$random,$random,$random};bm={$random,$random,$random,$random,$random};
  @(negedge ca);sa=1;@(negedge cb);sb=1;@(negedge ca);sa=0;@(negedge cb);sb=0;
  wait(!ab && !bb);repeat(32)@(negedge ca);
  if(na!=i+1 || nb!=i+1)$fatal(1,"lost packet");
 end
 $display("PASS 64 full-duplex CRC packets, 75/100MHz independent clocks, 200ppm B clock offset");$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
