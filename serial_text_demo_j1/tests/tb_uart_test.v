`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,busy=0,reply=0;always #5 clk=~clk;
reg[7:0] response=0;wire send;wire[7:0] data;
demo_uart_test #(.PERIOD(400)) dut(clk,rst,busy,reply,response,16'h1234,8'haf,1'b1,1'b0,3'd4,send,data);
integer cycle=0,waits=0,index=-1,heartbeats=0,acks=0;reg[215:0] expected={"UART RX=1234 LAST=AF SD=R",8'h0d,8'h0a};
always @(posedge clk)begin
 if(!rst)begin
 cycle=cycle+1;
 if(send)begin
 if(busy)$fatal(1,"send while busy");
 busy<=1;waits<=4;
 if(index>=0)begin
 if(data!==expected[215-index*8-:8])$fatal(1,"heartbeat corrupted or ACK interleaved index=%d",index);
 if(index==26)begin index=-1;heartbeats=heartbeats+1;end else index=index+1;
 end else if(data=="U")begin
 if(cycle<400)$fatal(1,"heartbeat before ten-second-equivalent interval");index=1;
 end else begin if(data!=="K")$fatal(1,"ACK byte lost or corrupted");acks=acks+1;end
 end else if(busy)begin if(waits==0)busy<=0;else waits<=waits-1;end
 end
end
initial begin
 repeat(6)@(negedge clk);rst=0;
 wait(index==5);
 // Queue responses while the complete 27-byte heartbeat owns the wire.
 repeat(40)begin @(negedge clk);reply=1;response="K";@(negedge clk);reply=0;end
 wait(heartbeats>=2 && acks==40);repeat(5)@(negedge clk);
 $display("PASS heartbeat interval, exact 27-byte framing and 40 queued ACKs without interleaving/loss");$finish;
end
initial begin #1000000;$fatal(1,"UART heartbeat timeout");end
endmodule
