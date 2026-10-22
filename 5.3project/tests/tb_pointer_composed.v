`timescale 1ns/1ps
module tb_pointer_composed;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=1;reg [11:0] x=0;reg [10:0] y=720;
wire de=x<1280 && y<720;wire frame=x==0 && y==720;
wire [11:0] x21;wire [10:0] y21;wire valid21;
wire [23:0] original,composed;
reg [10:0] cx=640;reg [9:0] cy=360;
photo_raster_delay #(.DELAY(21)) raster(.clk(clk),.rst(rst),.x(x21),.y(y21),.valid(valid21));
photo_pointer_overlay #(.DELAY(26)) reference(.clk(clk),.rst(rst),.frame_tick(frame),.enable(enable),.navigation_enable(1'b0),.de(de),.x(x),.y(y),
 .cursor_x(cx),.cursor_y(cy),.rgb_in(24'h345678),.rgb_out(original));
photo_pointer_overlay #(.DELAY(5)) lean(.clk(clk),.rst(rst),.frame_tick(frame),.enable(enable),.navigation_enable(1'b0),
 .de(valid21 && x21<1280 && y21<720),.x(x21),.y(y21),.cursor_x(cx),.cursor_y(cy),.rgb_in(24'h345678),.rgb_out(composed));
always @(posedge clk)begin
 if(rst)begin x<=0;y<=720;end
 else if(x==1649)begin x<=0;y<=y==749 ? 0:y+1'b1;end
 else x<=x+1'b1;
 #1;if(!rst && original!==composed)$fatal(1,"21+5 differs from 26 at %d,%d",x,y);
end
initial begin
 repeat(4)@(negedge clk);rst=0;
 repeat(1237500)@(negedge clk);
 if(!frame)$fatal(1,"frame alignment");enable=0;cx=1200;cy=40;
 repeat(55000)@(negedge clk);
 $display("PASS real raster21 + 5-clock pointer equals original 26-clock path over a full frame and visibility/cursor changes in blanking");$finish;
end
endmodule
