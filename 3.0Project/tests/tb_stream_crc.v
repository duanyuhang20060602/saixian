`timescale 1ns/1ps
module tb_stream_crc;
reg clk=0;always #5 clk=~clk;
reg rst=1,ack=0,feeding=0,drained=1;integer position=0,transaction=0,test;
reg [31:0] rom[0:7];reg [31:0] data;reg [20:0] limit;
wire start,pop,patch,pub,slot;wire [20:0] off,words,pa;wire [31:0] pd;
wire [3:0] error;wire [191:0] debug_data;wire [4:0] state;
wire valid=feeding && position<limit;
delta_player #(.VERIFY_STREAM(1),.WAIT_PATCH_DRAIN(1)) dut(clk,rst,1'b1,21'd472576,6'd27,start,off,words,ack,
 data,valid,pop,patch,pa,pd,1'b0,pub,slot,1'b0,1'b0,error,,,,state,debug_data,drained);
always @*begin
 if(transaction==1)data=rom[position];
 else if(test==1 && transaction==2)data=32'h0001c201;
 else if(test==2 && transaction==3)data=32'h0001c201;
 else if(test==3 && transaction==3)data=position==0 ? 32'd115198 : 32'd2;
 else if(test==3)data=position==0 ? 32'd115199 : 32'd1;
 else data=32'h0001c200;
end
always @(posedge clk)begin
 if(rst)begin ack<=0;feeding<=0;position<=0;transaction<=0;limit<=0;end
 else begin
  ack<=0;
  if(position==limit)feeding<=0;
  if(start && !feeding)begin feeding<=1;position<=0;limit<=words;transaction<=transaction+1;ack<=1;end
  if(pop)position<=position+1;
 end
end
initial begin
 rom[0]=384;rom[1]=1;rom[2]=2000000;rom[3]=0;rom[4]=32'haa74ac73;
 rom[5]=0;rom[6]=0;rom[7]=0;
 for(test=0;test<5;test=test+1)begin
  @(negedge clk);rst=1;drained=1;rom[1]=1;rom[4]=32'haa74ac73;repeat(5)@(negedge clk);rst=0;
  if(test==3)begin rom[1]=2;rom[4]=32'h5ae3f970;end
  if(test==4)begin
   wait(dut.state==3);@(negedge clk);drained=0;wait(dut.decode.state==5);
   repeat(5)@(negedge clk);if(pub || dut.decode.done)$fatal(1,"published before patch bus drain");
   drained=1;
  end
  wait(error || pub);@(negedge clk);
  if(test==0 && (error || !pub))$fatal(1,"valid precheck/decode CRC blocked first frame");
  if(test==1 && (error!=7 || pub || dut.decode_busy))$fatal(1,"precheck corruption not isolated as E37");
  if(test==2 && (error!=3 || pub || debug_data[31:0]!=32'h1c201))$fatal(1,"bad decode command not isolated E33");
  if(test==3 && (error!=8 || pub))$fatal(1,"decode CRC mismatch not isolated E38");
  if(test==4 && (error || !pub))$fatal(1,"drain acknowledgement did not resume publication");
 end
 $display("PASS stream CRC: precheck before frame writes; E37/E33/E38 block publication; no completion before patch drain; valid stream publishes");$finish;
end
initial begin #100000;$fatal(1,"stream CRC test timeout");end
endmodule
