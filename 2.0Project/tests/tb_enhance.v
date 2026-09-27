`timescale 1ns/1ps
module tb_enhance;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0,vs=0,ft=0;reg [10:0] x=0;reg [9:0] y=0;
reg [23:0] rgb=0;reg [1:0] mode=0,strength=1;
wire [23:0] out;wire od,ov;wire [10:0] ox;wire [9:0] oy;wire [1:0] gain;
saixian_adaptive_enhance #(.WIDTH(32),.SPLIT_X(16)) dut(clk,rst,de,vs,ft,1'b1,x,y,rgb,mode,strength,out,od,ov,ox,oy,gain);
reg [23:0] expected[0:6];reg [10:0] ex[0:6];reg [9:0] ey[0:6];reg [6:0] ed=0;
integer i,j,k,checks=0;
always @(posedge clk) if(!rst) begin
    for(k=6;k>0;k=k-1) begin expected[k]=expected[k-1];ex[k]=ex[k-1];ey[k]=ey[k-1];end
    expected[0]=rgb;ex[0]=x;ey[0]=y;ed={ed[5:0],de};
    #1;
    if(od!==ed[6]) $fatal(1,"DE latency mismatch");
    if(od) begin
        if(ox!==ex[6] || oy!==ey[6]) $fatal(1,"coordinate mismatch");
        if(mode==0 || (mode==2 && ox<16)) begin
            if(out!==expected[6]) $fatal(1,"bypass mismatch x=%d %h %h",ox,out,expected[6]);
        end
        if(^out===1'bx) $fatal(1,"uninitialized row RAM reached output");
        checks=checks+1;
    end
end
task frame; input [7:0] level;begin
    for(j=0;j<6;j=j+1) begin
        for(i=0;i<32;i=i+1) begin @(negedge clk);de=1;x=i;y=j;rgb={level,level,level};end
        @(negedge clk);de=0;repeat(7) @(negedge clk);
    end
    repeat(10) @(negedge clk);
end endtask
initial begin
    repeat(4) @(negedge clk);rst=0;
    frame(64);mode=1;frame(0);if(out!==0) $fatal(1,"blanking not black");
    frame(255);mode=2;frame(80);mode=0;frame(127);
    if(checks!=960) $fatal(1,"pixel count mismatch %d",checks);
    $display("PASS enhancement bypass/split, RGB/DE/XY alignment, border masks");$finish;
end
endmodule
