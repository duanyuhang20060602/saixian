`timescale 1ns/1ps
module tb;
parameter BAUD=921600;
reg ca=0,cb=0,rst=1,sa=0,sb=0;
always #6.666667 ca=~ca;always #5 cb=~cb;
reg [159:0] ma,mb;wire ta,tb_,ba,bb,ga,gb,ea,eb;wire[159:0] ra,rb;
photo_uart #(.CLK_HZ(75000000),.BAUD(BAUD),.PULSE_PAYLOAD(1),.PAYLOAD_BYTES(18)) a(ca,rst,tb_,ta,sa,ma,ba,ga,ra,ea);
photo_uart #(.CLK_HZ(100000000),.BAUD(BAUD),.PULSE_PAYLOAD(1),.PAYLOAD_BYTES(18)) b(cb,rst,ta,tb_,sb,mb,bb,gb,rb,eb);
integer na=0,nb=0,i;time started,elapsed;
always @(posedge ca)if(!rst && ga)begin if(ra!==mb)$fatal(1,"B to A corrupt");na=na+1;end
always @(posedge cb)if(!rst && gb)begin if(rb!==ma)$fatal(1,"A to B corrupt");nb=nb+1;end
initial begin
 repeat(8)@(negedge ca);rst=0;started=$time;
 for(i=0;i<16;i=i+1)begin
 ma={$random,$random,$random,$random,$random};mb={$random,$random,$random,$random,$random};ma[15:0]=0;mb[15:0]=0;
 @(negedge ca);sa=1;@(negedge ca);sa=0;
 @(negedge cb);sb=1;@(negedge cb);sb=0;
 wait(!ba && !bb);repeat(30)@(negedge ca);
 end
 elapsed=$time-started;
 if(na!=16 || nb!=16)$fatal(1,"missing packet %d %d",na,nb);
 $display("PASS asynchronous UART BAUD=%d A_to_B=%d B_to_A=%d elapsed_ns=%d",BAUD,nb,na,elapsed);$finish;
end
initial begin #100000000;$fatal(1,"timeout");end
endmodule
