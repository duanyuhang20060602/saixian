`timescale 1ns/1ps
module tb_vga_720;
reg clk=0;always #5 clk=~clk;reg rst=1,start=0,pv=0;reg [23:0] rgb=0;
wire ov,busy,fault;wire [23:0] out;
saixian_load_scaler #(.OUT_WIDTH(1280),.OUT_HEIGHT(720)) dut(clk,rst,start,16'd640,16'd480,pv,rgb,ov,out,busy,fault);
integer x,y,n=0,sx,sy,ox,oy,rows=3;
integer xstep=(639*65536)/1279,ystep=(479*65536)/719;
reg [23:0] p,expected;
function [23:0] picture;
 input integer xx,yy;reg [7:0] r,g,b;
 begin r=xx%7==0 ? 255:17;g=yy%5==0 ? 239:37;b=(xx+yy)%2==0 ? 247:9;picture={r,g,b};end
endfunction
always @(negedge clk)begin
 if(fault)$fatal(1,"720 VGA scheduling fault");
 if(ov)begin
  ox=n%1280;oy=n/1280;sx=(ox==1279) ? 639:((ox*xstep+32768)>>16);sy=(oy*ystep+32768)>>16;
  p=picture(sx,sy);expected={p[23:19],p[23:21],p[15:10],p[15:14],p[7:3],p[7:5]};
  if(out!==expected)$fatal(1,"VGA nearest 1280x720 x=%d y=%d got=%h expected=%h",ox,oy,out,expected);
  n=n+1;
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;repeat(40)@(negedge clk);
 for(y=0;y<rows;y=y+1)for(x=0;x<640;x=x+1)begin rgb=picture(x,y);pv=1;@(negedge clk);pv=0;repeat(191)@(negedge clk);end
 wait(!dut.v_run);repeat(30)@(negedge clk);
 if(n!=1280*((((rows-1)<<16)/ystep)+1))$fatal(1,"VGA prefix pixel count %d",n);
 $display("PASS VGA crisp nearest sampling and RGB565 at 1280x720: %d pixels",n);$finish;
end
initial begin #10000000;$fatal(1,"VGA prefix timeout");end
endmodule
