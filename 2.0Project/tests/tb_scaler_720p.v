`timescale 1ns/1ps
module tb_scaler_720p;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,valid=0;reg [15:0] w=640,h=480;
reg [23:0] pixel_in=0;wire ov,busy,fault;wire [23:0] rgb;
saixian_load_scaler #(.VERTICAL_PERIOD(1)) dut(clk,rst,start,w,h,valid,pixel_in,ov,rgb,busy,fault);
integer x,y,n=0,r,g,er,eg,case_id=0;
always @(negedge clk) if(ov) begin
    er=(n%1280)*255/1279;eg=(n/1280)*255/719;
    if(^rgb===1'bx || rgb[23:16]+10<er || rgb[23:16]>er+10 ||
       rgb[15:8]+6<eg || rgb[15:8]>eg+6 || rgb[7:0]!=8'd132)
        $fatal(1,"case=%0d output=%0d expected R/G=%0d/%0d actual=%h",case_id,n,er,eg,rgb);
    n=n+1;
end
task run_case;input [15:0] width,height;begin
    w=width;h=height;n=0;
    @(negedge clk);start=1;@(negedge clk);start=0;repeat(30) @(negedge clk);
    for(y=0;y<height;y=y+1) for(x=0;x<width;x=x+1) begin
        r=x*255/(width-1);g=y*255/(height-1);
        @(negedge clk);valid=1;pixel_in={r[7:0],g[7:0],8'd132};
        @(negedge clk);valid=0;repeat(4) @(negedge clk);
    end
    repeat(3000) @(negedge clk);
    if(n!=921600 || busy || fault) $fatal(1,"case=%d incomplete n=%d busy=%b fault=%b",case_id,n,busy,fault);
    $display("PASS %0dx%0d -> 1280x720: 921600 pixels, 2D gradient, no overrun",width,height);
    case_id=case_id+1;
end endtask
initial begin
    repeat(4) @(negedge clk);rst=0;
    run_case(640,480);run_case(641,361);run_case(1920,1080);
    $finish;
end
initial begin #300000000;$fatal(1,"timeout");end
endmodule
