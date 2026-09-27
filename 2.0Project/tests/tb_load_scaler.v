`timescale 1ns/1ps
module tb_load_scaler;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,valid=0;
reg [15:0] w=4,h=3;
reg [23:0] rgb=0;
wire out_valid,busy,fault;wire [23:0] out;
saixian_load_scaler #(.OUT_WIDTH(7),.OUT_HEIGHT(5),.VERTICAL_PERIOD(1)) dut(clk,rst,start,w,h,valid,rgb,out_valid,out,busy,fault);
integer n=0,x,y,expected,tolerance;
reg check_ramp=0;
always @(negedge clk) if(out_valid) begin
    if(check_ramp) begin
        // RGB565 line-store precision: <= 9 levels from ideal interpolation.
        expected=(n%7)*20+(n/7)*20;
        if(out[23:16]+9<expected || out[23:16]>expected+9)
            $fatal(1,"ramp mismatch pixel %0d expected %0d actual %0d",n,expected,out[23:16]);
    end else if(out!==24'hFFFFFF) $fatal(1,"constant or native pixel corrupted: %h",out);
    n=n+1;
end
task launch;begin @(negedge clk);start=1;@(negedge clk);start=0;repeat(30) @(negedge clk);end endtask
task pixel;input [23:0] p;begin
    @(negedge clk);rgb=p;valid=1;@(negedge clk);valid=0;repeat(32) @(negedge clk);
end endtask
initial begin
    repeat(4) @(negedge clk);rst=0;launch;
    for(y=0;y<3;y=y+1) for(x=0;x<4;x=x+1) pixel(24'hFFFFFF);
    repeat(50) @(negedge clk);
    if(n!=35 || busy || fault) $fatal(1,"constant scaling count=%0d busy=%b fault=%b",n,busy,fault);
    n=0;check_ramp=1;launch;
    for(y=0;y<3;y=y+1) for(x=0;x<4;x=x+1) begin
        expected=x*40+y*40;pixel({expected[7:0],expected[7:0],expected[7:0]});
    end
    repeat(50) @(negedge clk);
    if(n!=35 || busy || fault) $fatal(1,"ramp scaling incomplete");
    n=0;check_ramp=0;w=7;h=5;launch;
    repeat(35) pixel(24'hFFFFFF);
    if(n!=35 || busy || fault) $fatal(1,"native bypass failed");
    $display("PASS bilinear constant, 2D ramp, endpoints, count, native bypass");$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
