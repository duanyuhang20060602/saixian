`timescale 1ns/1ps
module fifo_pair #(parameter DEPTH=2048,AW=11,RAM_HEAD=DEPTH)(input clk,rst,we,re,input [31:0] wd,output reg done=0);
wire [31:0] data,ref_data;wire empty,full,ref_empty,ref_full;wire [AW:0] used,ref_used;
photo_audio_fifo #(.DEPTH(DEPTH),.AW(AW),.RAM32_HEAD(RAM_HEAD)) dut(clk,rst,we,wd,re,data,empty,full,used);
photo_audio_fifo_ref #(.DEPTH(DEPTH),.AW(AW)) ref_dut(clk,rst,we,wd,re,ref_data,ref_empty,ref_full,ref_used);
integer reads=0,checks=0;
always @(posedge clk)begin
 if(!rst && re && !empty)reads=reads+1;
 #1;
 if({empty,full,used}!=={ref_empty,ref_full,ref_used})$fatal(1,"FIFO flags/count differ depth=%0d",DEPTH);
 if(reads>0 && data!==ref_data)$fatal(1,"FIFO PCM/data hold differs depth=%0d read=%0d",DEPTH,reads);
 checks=checks+1;
 if(checks==180000)begin
  if(reads<20000)$fatal(1,"insufficient FIFO coverage");
  $display("PASS configured %0d-sample PCM FIFO: %0d exact reads, full/empty/wrap/reset and simultaneous read/write",DEPTH,reads);done=1;
 end
end
endmodule
module tb;
reg clk=0,rst=1,we=0,re=0;always #5 clk=~clk;
reg [31:0] random_state=32'h8c59d317;wire a_done,b_done,c_done;
fifo_pair a(clk,rst,we,re,random_state,a_done);
fifo_pair #(.DEPTH(8192),.AW(13)) b(clk,rst,we,re,random_state,b_done);
fifo_pair #(.DEPTH(8192),.AW(13),.RAM_HEAD(4096)) c(clk,rst,we,re,random_state,c_done);
integer n;
initial begin
 repeat(4)@(negedge clk);rst=0;
 for(n=0;n<180010;n=n+1)begin
  @(negedge clk);random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
  we=n<10000 ? 1:n<20000 ? 0:random_state[1];
  re=n<10000 ? 0:n<20000 ? 1:random_state[4];
  rst=n>20000 && n%30017==7;
 end
 wait(a_done && b_done && c_done);$finish;
end
endmodule
