`timescale 1ns/1ps
module tb;
reg clk=0,rst=1;always #5 clk=~clk;reg [23:0] source=0;wire [23:0] a,b,ma,mb;
reg [31:0] random=32'h9bc5891d;integer i,checks=0;
photo_award_delay old(.clk(clk),.rst(rst),.rgb_in(source),.rgb(a),.menu_rgb(ma));
photo_award_delay_lut dut(.clk(clk),.rst(rst),.rgb_in(source),.rgb(b),.menu_rgb(mb));
always @(posedge clk)begin #1;if({a,ma}!=={b,mb})$fatal(1,"award video taps changed %h/%h menu %h/%h",a,b,ma,mb);checks=checks+1;end
initial begin
 for(i=0;i<250000;i=i+1)begin
  @(negedge clk);random=random^(random<<13);random=random^(random>>17);random=random^(random<<5);
  source=random[23:0];rst=i<4 || (i%13001)<3;
 end
 $display("PASS 250000 exact seven/twelve-clock video tap pairs, arbitrary 24-bit colors, repeated resets, no added latency");$finish;
end
endmodule
