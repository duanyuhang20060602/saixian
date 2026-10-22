`timescale 1ns/1ps
module spi_case #(parameter DIV=0)(output reg done=0,output reg [31:0] elapsed=0);
reg clk=0,rst=1,cs=1,request=0,miso=1;always #5 clk=~clk;
wire dclk,ack;wire [7:0] data;integer bytes=0,bit_index=0,slave_byte=0;reg [31:0] cycles=0,start_cycle;
spi_master #(.FAST_READ_STREAM(1)) dut(.sys_clk(clk),.rst(rst),.nCS(),.DCLK(dclk),.MOSI(),.MISO(miso),
 .CPOL(1'b1),.CPHA(1'b1),.nCS_ctrl(cs),.clk_div(16'(DIV)),.wr_req(request),.read_stream(1'b1),.read_continue(bytes<127),.wr_ack(ack),.data_in(8'hff),.data_out(data));
function [7:0] expected;input integer n;begin expected=(n*73)^8'had;end endfunction
reg [7:0] slave_data;
always @(negedge dclk)if(!cs)begin slave_data=expected(slave_byte);miso=slave_data[7-bit_index];end
time previous_rise=0;
always @(posedge dclk)if(!cs)begin
 if(previous_rise!=0 && $time-previous_rise<(DIV==0 ? 40:80))$fatal(1,"SD SPI exceeds configured clock");
 previous_rise=$time;
 if(bit_index==7)begin bit_index=0;slave_byte=slave_byte+1;end else bit_index=bit_index+1;
end
always @(posedge clk)begin
 cycles<=cycles+1;
 if(!rst && !cs && !done)begin
  if(ack)begin
   if(data!==expected(bytes))$fatal(1,"SPI byte corruption div=%0d byte=%0d got=%h",DIV,bytes,data);
   bytes=bytes+1;request<=0;
   if(bytes==128)begin elapsed=cycles-start_cycle;done=1;end
  end else if(dut.state==0)request<=1;
 end
end
initial begin repeat(4)@(negedge clk);rst=0;repeat(3)@(negedge clk);cs=0;request=1;start_cycle=cycles;end
endmodule
module tb;
wire a,b;wire [31:0] fast_cycles,old_cycles;
spi_case fast(a,fast_cycles);spi_case #(.DIV(2)) baseline(b,old_cycles);
initial begin wait(a && b);
 if(fast_cycles*10>=old_cycles*6)$fatal(1,"SPI streaming throughput gain missing");
 $display("PASS existing TF SPI contract: 128 exact bytes, div0=%0d and div2=%0d system clocks, at most 25MHz/12.5MHz, first/last byte and byte-boundary continuity; configuration comparison only, production TF driver unchanged",fast_cycles,old_cycles);$finish;
end
initial begin #1000000;$fatal(1,"SPI speed timeout");end
endmodule
