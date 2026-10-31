`timescale 1ns/1ps
module tb_thumbnail_overlay;
reg clk=0,rst=1,ft=0,en=1,cv=1,de=1,done=0;
always #5 clk=~clk;
reg [1:0] cs=1;reg [5:0] identity=5;reg [11:0] x=1100;reg [10:0] y=540;
wire req,cancel,visible;wire [1:0] slot;wire [12:0] address;wire [23:0] rgb;
photo_thumbnail_overlay dut(.clk(clk),.rst(rst),.frame_tick(ft),.enable(en),.cache_valid(cv),.cache_slot(cs),.identity(identity),
 .de(de),.x(x),.y(y),.request(req),.slot(slot),.cancel(cancel),.done(done),.data(16'hf800),.address(address),.visible(visible),.rgb_in(24'h123456),.rgb_out(rgb));
task clocks;input integer n;begin repeat(n)@(negedge clk);end endtask
task tick;begin ft=1;clocks(1);ft=0;clocks(1);end endtask
task complete;
 begin wait(req!=done);clocks(8);done=req;clocks(8);if(visible)$fatal(1,"midframe arm");tick();if(!visible)$fatal(1,"completed cache not visible");end
endtask
initial begin
 clocks(8);rst=0;complete();if(rgb!==24'hff0000)$fatal(1,"pixel expansion");
 en=0;#1;if(visible)$fatal(1,"disabled navigation");clocks(1);if(rgb!==24'h123456)$fatal(1,"registered disabled pixel gate");clocks(8);en=1;complete();
 cv=0;#1;if(visible)$fatal(1,"invalid cache visible");clocks(8);cv=1;complete();
 identity=9;#1;if(visible)$fatal(1,"same-slot new image visible");clocks(2);
 wait(req!=done);clocks(4);identity=13;clocks(2);
 if(!cancel || visible)$fatal(1,"old in-flight identity not cancelled");
 identity=9;clocks(4);if(!cancel)$fatal(1,"cancellation lost when identity reverted");
 done=req;clocks(8);if(visible)$fatal(1,"cancelled pixels visible");complete();
 cs=2;identity=14;#1;if(visible)$fatal(1,"replacement slot visible");complete();
 cs=3;identity=15;clocks(8);tick();if(visible || !cancel)$fatal(1,"invalid slot accepted");
 $display("PASS preview gating: menu/transition, invalidation, same-slot identity, sticky cancellation, slot replacement and frame-boundary re-arm");$finish;
end
initial begin #20000;$fatal(1,"overlay timeout");end
endmodule
