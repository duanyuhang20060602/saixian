`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,ft=0;always #5 clk=~clk;
reg [11:0] x=1220;reg [10:0] y=360;wire [23:0] rgb;
photo_pointer_overlay #(.DELAY(5),.NAVIGATION_BUTTON(0)) dut(.clk(clk),.rst(rst),.frame_tick(ft),.enable(1'b1),
 .de(1'b1),.navigation_enable(1'b1),.x(x),.y(y),.cursor_x(11'd100),.cursor_y(10'd100),.rgb_in(24'h345678),.rgb_out(rgb));
integer xx,yy;
initial begin
 repeat(5)@(negedge clk);rst=0;ft=1;@(negedge clk);ft=0;
 for(yy=328;yy<392;yy=yy+8)for(xx=1192;xx<1256;xx=xx+8)begin
  x=xx;y=yy;repeat(7)@(negedge clk);
  if(rgb!==24'h345678)$fatal(1,"legacy next arrow still drawn");
 end
 x=1200;y=44;repeat(7)@(negedge clk);
 if(rgb===24'h345678)$fatal(1,"menu launcher was removed with arrow");
 $display("PASS navigation arrow removed across its old bounds; menu launcher and cursor pipeline retained");$finish;
end
endmodule
