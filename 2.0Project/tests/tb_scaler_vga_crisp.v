`timescale 1ns/1ps
// Real VGA geometry; independent Q16 nearest-pixel and RGB565 reference.
module tb_scaler_vga_crisp;
reg clk=0; always #5 clk=~clk;
reg rst=1,start=0,pv=0;
reg [23:0] rgb=0;
wire ov,busy,fault;
wire [23:0] out;
saixian_load_scaler dut(clk,rst,start,16'd640,16'd480,pv,rgb,ov,out,busy,fault);
integer n=0,sx,sy,ox,oy,x,y,cycle=0,last_cycle=-1000;
integer xstep=(639*65536)/1279,ystep=(479*65536)/719;
reg [23:0] expected;
function [23:0] source_pixel;
    input integer px,py;
    reg [7:0] r,g,b;
    begin
        // Thin strokes, checkerboard and non-565-exact colors detect mixing.
        r=(px%7==0) ? 8'd255 : 8'd17;
        g=(py%5==0) ? 8'd239 : 8'd37;
        b=((px+py)%2==0) ? 8'd247 : 8'd9;
        source_pixel={r,g,b};
    end
endfunction
function [23:0] quantized_pixel;
    input [23:0] p;
    begin quantized_pixel={p[23:19],p[23:21],p[15:10],p[15:14],p[7:3],p[7:5]}; end
endfunction
always @(negedge clk) begin
    cycle=cycle+1;
    if(!rst && fault) $fatal(1,"VGA scaler scheduling fault");
    if(ov) begin
        if(n>=921600) $fatal(1,"extra output pixel");
        ox=n%1280;oy=n/1280;
        sx=(ox==1279) ? 639 : ((ox*xstep+32768)>>16);
        sy=(oy==719) ? 479 : ((oy*ystep+32768)>>16);
        expected=quantized_pixel(source_pixel(sx,sy));
        if(out!==expected)
            $fatal(1,"VGA blend/alignment x=%0d y=%0d got=%h expected=%h",ox,oy,out,expected);
        if(cycle-last_cycle<16) $fatal(1,"write pacing changed");
        last_cycle=cycle;n=n+1;
    end
end
initial begin
    repeat(4) @(negedge clk);rst=0;
    @(negedge clk);start=1;@(negedge clk);start=0;
    repeat(40) @(negedge clk);
    for(y=0;y<480;y=y+1) for(x=0;x<640;x=x+1) begin
        @(negedge clk);rgb=source_pixel(x,y);pv=1;
        @(negedge clk);pv=0;
        // 96-clock gap approximates the production SPI 24-bit pixel interval.
        repeat(96) @(negedge clk);
    end
    repeat(45000) @(negedge clk);
    if(n!=921600 || busy || fault) $fatal(1,"VGA incomplete n=%0d busy=%b fault=%b",n,busy,fault);
    $display("PASS VGA crisp: 921600 exact nearest pixels, endpoints, RGB565, pacing");
    $finish;
end
initial begin #1000000000; $fatal(1,"VGA test timeout"); end
endmodule
