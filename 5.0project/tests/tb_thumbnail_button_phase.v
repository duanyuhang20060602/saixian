`timescale 1ns/1ps
module tb_thumbnail_phase;
reg clk=0,rst=1,ft=0;
always #5 clk=~clk;
wire [11:0] x;wire [10:0] y;wire raster_valid;
photo_raster_delay #(.DELAY(26),.START_Y(313)) raster(.clk(clk),.rst(rst),.x(x),.y(y),.valid(raster_valid));
wire req,visible,cancel;wire [1:0] slot;wire [12:0] address;wire [23:0] rgb;
reg done=0;reg [15:0] data=0;integer checked=0;
function [15:0] pattern;
 input integer px,py;
 begin pattern={px[4:0],py[5:0],(px[4:0]^py[4:0])};end
endfunction
function [23:0] expand;
 input [15:0] p;
 begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end
endfunction
photo_thumbnail_overlay #(.X(1096),.Y(315)) dut(.clk(clk),.rst(rst),.frame_tick(ft),.enable(1'b1),.cache_valid(1'b1),.cache_slot(2'd1),.identity(6'd5),
 .de(raster_valid && x<1280 && y<720),.x(x),.y(y),.request(req),.slot(slot),.cancel(cancel),
 .done(done),.data(data),.address(address),.visible(visible),.rgb_in(24'h102030),.rgb_out(rgb));
always @(posedge clk)begin
 data<=pattern(address%112,address/112);
 #1;
 if(!rst && raster_valid && y>=315 && y<405 && x>=1096 && x<1256)begin
  if(!visible || rgb!==expand(pattern((x-1096)*7/10,(y-315)*7/10)))$fatal(1,"phase x=%d y=%d rgb=%h expected=%h address=%d",x,y,rgb,expand(pattern((x-1096)*7/10,(y-315)*7/10)),address);
  checked=checked+1;
 end
end
initial begin
 repeat(6)@(negedge clk);rst=0;
 wait(req!=done);repeat(12)@(negedge clk);done=req;
 repeat(10)@(negedge clk);ft=1;@(negedge clk);ft=0;
 wait(y==406);@(negedge clk);
 if(checked!=14400)$fatal(1,"phase test incomplete pixels=%d",checked);
 $display("PASS raster26: all 14400 scaled pixels, exact 112x63 to 160x90 mapping, zero added RGB latency");$finish;
end
initial begin #2000000;$fatal(1,"phase timeout");end
endmodule
