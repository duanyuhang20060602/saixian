`timescale 1ns/1ps
module tb_single_plate;
reg clk=0;always #10 clk=~clk;reg rst=1,ack=0,valid=0,commit=0;
wire req,pop,patch,pub,slot;wire [20:0] off,len,pa;wire [31:0] pd;
wire [3:0] error;wire [4:0] state;wire [5:0] descriptor;
reg [31:0] command[0:1];reg [31:0] desc[0:7];reg [3:0] pointer,left;reg mode;integer patches=0;
wire [31:0] data=mode ? command[pointer] : desc[pointer];
delta_player #(.SINGLE_PLATE(1),.FRAME_WORDS(4),.VERIFY_STREAM(1),.WAIT_PATCH_DRAIN(1)) dut(
 clk,rst,1'b1,21'd512,6'd1,req,off,len,ack,data,valid,pop,
 patch,pa,pd,1'b1,pub,slot,commit,1'b0,error,,,,state,,1'b1);
always @(posedge clk)begin
 if(rst)begin ack<=0;valid<=0;pointer<=0;left<=0;mode<=0;commit<=0;patches<=0;end
 else begin
  commit<=pub;
  if(req && !ack && !valid)begin ack<=1;pointer<=0;left<=len;mode<=off==384;end
  if(ack && !req)begin ack<=0;valid<=1;end
  if(valid && pop)begin pointer<=pointer+1;left<=left-1;if(left==1)valid<=0;end
  if(patch)begin if(pd!=32'hA55A1234 || pa>=8)$fatal(1,"bootstrap patch corruption");patches<=patches+1;end
 end
end
initial begin
 command[0]=32'h80000004;command[1]=32'hA55A1234;
 desc[0]=384;desc[1]=2;desc[2]=300000000;desc[3]=0;
 desc[4]=32'hd68d9b50;desc[5]=0;desc[6]=0;desc[7]=0;
 repeat(8)@(negedge clk);rst=0;
 wait(state==10);repeat(100)@(negedge clk);
 if(error || req || patch || patches!=8 || pub!=1 || slot!=0)$fatal(1,"bootstrap does not release command port safely");
 $display("PASS single_plate: verified bootstrap in both buffers, publication acknowledged, command port released with no later requests");$finish;
end
initial begin #100000;$fatal(1,"single plate timeout");end
endmodule
