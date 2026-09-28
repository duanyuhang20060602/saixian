`timescale 1ns/1ps
// Fast regression for the Q16 nonzero-fraction/zero-Q8-weight bug near row 707.
// Seed only raster counters; all tail pixels still pass through real row RAMs.
module tb_scaler_vga_tail;
reg clk=0;always #5 clk=~clk;
reg rst=1,start=0,pv=0;
reg [23:0] rgb=0;
wire ov,busy,fault;
wire [23:0] out;
saixian_load_scaler dut(clk,rst,start,16'd640,16'd480,pv,rgb,ov,out,busy,fault);
integer x,y,n=704*1280,ox,oy,sx,sy,cycle=0,last_cycle=-1000;
integer xstep=(639*65536)/1279,ystep=(479*65536)/719;
reg [23:0] expected;
function [23:0] source_pixel;
 input integer px,py;
 reg [7:0] r,g,b;
 begin
  r=(px%7==0)?255:17;g=(py%5==0)?239:37;b=((px+py)%2==0)?247:9;
  source_pixel={r,g,b};
 end
endfunction
function [23:0] quantized_pixel;
 input [23:0] p;
 begin quantized_pixel={p[23:19],p[23:21],p[15:10],p[15:14],p[7:3],p[7:5]};end
endfunction
always @(negedge clk) begin
 cycle=cycle+1;
 if(!rst && fault) $fatal(1,"tail scheduling fault");
 if(ov) begin
  if(n>=921600) $fatal(1,"extra tail pixel");
  ox=n%1280;oy=n/1280;
  sx=(ox==1279)?639:((ox*xstep+32768)>>16);
  sy=(oy==719)?479:((oy*ystep+32768)>>16);
  expected=quantized_pixel(source_pixel(sx,sy));
  if(out!==expected) $fatal(1,"tail x=%d y=%d got=%h expected=%h",ox,oy,out,expected);
  if(cycle-last_cycle<16) $fatal(1,"tail pacing");
  last_cycle=cycle;n=n+1;
 end
end
initial begin
 repeat(4) @(negedge clk);rst=0;
 @(negedge clk);start=1;@(negedge clk);start=0;
 repeat(40) @(negedge clk);
 // Start after the divider completes. Rows 468..470 warm the row cache.
 dut.in_y=468;dut.write_bank=0;dut.vy=704;dut.ypos=704*ystep;
 for(y=468;y<480;y=y+1) for(x=0;x<640;x=x+1) begin
  @(negedge clk);rgb=source_pixel(x,y);pv=1;
  @(negedge clk);pv=0;repeat(96) @(negedge clk);
 end
 repeat(45000) @(negedge clk);
 if(n!=921600 || busy || fault) $fatal(1,"tail incomplete n=%d",n);
 $display("PASS 20480 VGA tail pixels: row 707/710/713/716 and exact final endpoint");$finish;
end
initial begin #20000000;$fatal(1,"tail timeout");end
endmodule
