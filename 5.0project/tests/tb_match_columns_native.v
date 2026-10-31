`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg[9:0] address=0;wire[8:0] data;
photo_match_columns d(clk,address,data);
function[8:0] expected;input integer x;begin
 expected=0;
 if(x>=64 && x<96)expected={4'd1,5'(x-64)};
 else if(x>=104 && x<136)expected={4'd2,5'(x-104)};
 else if(x>=144 && x<176)expected={4'd3,5'(x-144)};
 else if(x>=464 && x<496)expected={4'd4,5'(x-464)};
 else if(x>=504 && x<536)expected={4'd5,5'(x-504)};
 else if(x>=544 && x<576)expected={4'd6,5'(x-544)};
 else if(x>=248 && x<268)expected={4'd7,5'(x-248)};
 else if(x>=272 && x<292)expected={4'd8,5'(x-272)};
 else if(x>=302 && x<307)expected={4'd9,5'(x-302)};
 else if(x>=320 && x<340)expected={4'd10,5'(x-320)};
 else if(x>=344 && x<364)expected={4'd11,5'(x-344)};
end endfunction
integer i,x;
initial begin
 repeat(3)@(negedge clk);
 for(i=0;i<1024;i=i+1)begin
  x=(i*37)%1024;@(negedge clk);address=x;@(posedge clk);#1;
  if(data!==expected(x))$fatal(1,"native9K column address=%d got=%h expected=%h",x,data,expected(x));
 end
 $display("PASS native9K column ROM: all1024 addresses, exact score/timer/colon group and pixel offset, one-clock read");$finish;
end
endmodule
