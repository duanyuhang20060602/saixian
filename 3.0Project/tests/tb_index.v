`timescale 1ns/1ps
module tb_index;
reg clk=0;always #5 clk=~clk;
reg rst=1,ack=0,issued=0;integer position=0,test;
reg [31:0] descriptor_words[0:7];
wire start,pop,patch,pub,slot;wire [20:0] off,words,pa;wire [31:0] pd;
wire [3:0] error;wire [31:0] late;wire [5:0] source,descriptor;wire [4:0] state;
wire valid=issued && position<8;
delta_player dut(clk,rst,1'b1,21'd472576,6'd27,start,off,words,ack,
 descriptor_words[position],valid,pop,patch,pa,pd,1'b0,pub,slot,1'b0,1'b0,error,late,source,descriptor,state,,1'b1);
always @(posedge clk)begin
 if(rst)begin ack<=0;issued<=0;position<=0;end
 else begin
  ack<=0;
  if(start && !issued)begin issued<=1;ack<=1;end
  if(pop)position<=position+1;
 end
end
reg [3:0] wanted;
initial begin
 for(test=0;test<9;test=test+1)begin
  @(negedge clk);rst=1;repeat(4)@(negedge clk);
  descriptor_words[0]=384;descriptor_words[1]=30738;descriptor_words[2]=2000000;
  descriptor_words[3]=32'h28422eae;descriptor_words[4]=0;descriptor_words[5]=0;descriptor_words[6]=0;descriptor_words[7]=0;
  wanted=0;
  case(test)
   1:begin descriptor_words[0]=385;wanted=11;end
   2:begin descriptor_words[0]=128;wanted=11;end
   3:begin descriptor_words[0]=2097536;wanted=11;end
   4:begin descriptor_words[1]=0;wanted=12;end
   5:begin descriptor_words[1]=2097152;wanted=12;end
   6:begin descriptor_words[0]=472448;descriptor_words[1]=256;wanted=13;end
   7:begin descriptor_words[2]=0;wanted=14;end
   8:begin descriptor_words[2]=500000001;wanted=14;end
  endcase
  rst=0;wait(error!=0 || state==3);@(negedge clk);
  if(error!==wanted)$fatal(1,"index case %d error=%h want=%h",test,error,wanted);
 end
 $display("PASS index: valid descriptor and misaligned/range offset, length, file boundary and duration failures distinguished as E3B/E3C/E3D/E3E");$finish;
end
initial begin #100000;$fatal(1,"index timeout");end
endmodule
