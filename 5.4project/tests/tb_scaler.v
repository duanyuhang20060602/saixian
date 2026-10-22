`timescale 1ns/1ps
module scaler_case #(parameter SW=64,SH=32,PACE=1,PIXEL_PERIOD=600,ROWS=SH)(output reg done=0);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,start=0,valid=0;reg [23:0] rgb=0;wire ov,busy,fault;wire [23:0] pixel;
 saixian_load_scaler #(.OUT_WIDTH(1280),.OUT_HEIGHT(720),.VERTICAL_PERIOD(PACE)) dut(
  .clk(clk),.rst(rst),.start(start),.source_width(16'(SW)),.source_height(16'(SH)),
  .pixel_valid(valid),.pixel_in(rgb),.pixel_out_valid(ov),.pixel_out(pixel),.busy(busy),.fault(fault));
 function [23:0] source_rgb;
  input integer x,y;integer r,g,b;
  begin r=(3*x+7*y)&255;g=(11*x+5*y)&255;b=(9*x+13*y)&255;source_rgb={r[7:0],g[7:0],b[7:0]};end
 endfunction
 function [23:0] horizontal;
  input integer xx,sy;integer p,lo,hi,w,c0,c1,r,g,b;reg [23:0] l,h;reg [15:0] p565;
  begin
   p=xx==1279 ? ((SW-1)<<16) : xx*(((SW-1)<<16)/1279);
   lo=p>>16;hi=lo+((p&65535)!=0);w=(p>>8)&255;l=source_rgb(lo,sy);h=source_rgb(hi,sy);
   c0=l[23:16];c1=h[23:16];r=c0+(((c1-c0)*w)>>>8);
   c0=l[15:8];c1=h[15:8];g=c0+(((c1-c0)*w)>>>8);
   c0=l[7:0];c1=h[7:0];b=c0+(((c1-c0)*w)>>>8);
   p565={5'(r>>3),6'(g>>2),5'(b>>3)};
   horizontal={p565[15:11],p565[15:13],p565[10:5],p565[10:9],p565[4:0],p565[4:2]};
  end
 endfunction
 function [23:0] expected;
  input integer xx,yy;integer p,lo,hi,w,c0,c1,r,g,b;reg [23:0] l,h;
  begin
   p=yy==719 ? ((SH-1)<<16) : yy*(((SH-1)<<16)/719);
   lo=p>>16;hi=lo+((p&65535)!=0);w=(p>>8)&255;l=horizontal(xx,lo);h=horizontal(xx,hi);
   c0=l[23:16];c1=h[23:16];r=c0+(((c1-c0)*w)>>>8);
   c0=l[15:8];c1=h[15:8];g=c0+(((c1-c0)*w)>>>8);
   c0=l[7:0];c1=h[7:0];b=c0+(((c1-c0)*w)>>>8);
   expected={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 integer x,y,count=0,rows_expected;
 always @(negedge clk)begin
  if(fault)begin $fatal(1,"FAIL scaler fault SW=%0d SH=%0d pace=%0d count=%0d",SW,SH,PACE,count);end
  if(ov)begin
   if(pixel!==expected(count%1280,count/1280))begin
    $fatal(1,"FAIL scaler SW=%0d count=%0d got=%h expected=%h",SW,count,pixel,expected(count%1280,count/1280));end
   count=count+1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;repeat(40)@(negedge clk);
  for(y=0;y<ROWS;y=y+1)for(x=0;x<SW;x=x+1)begin
   rgb=source_rgb(x,y);valid=1;@(negedge clk);valid=0;repeat(PIXEL_PERIOD-1)@(negedge clk);
  end
  if(ROWS==SH)wait(!busy);else begin wait(!dut.v_run);repeat(20)@(negedge clk);end
  repeat(3)@(negedge clk);#1;
  rows_expected=ROWS==SH ? 720 : (((ROWS-1)<<16)/(((SH-1)<<16)/719))+1;
  if(count!=1280*rows_expected)begin $fatal(1,"FAIL scaler count SW=%0d got=%0d expected=%0d",SW,count,1280*rows_expected);end
  $display("PASS scaler SW=%0d SH=%0d pace=%0d rows=%0d output=%0d golden bilinear",SW,SH,PACE,ROWS,count);done=1;
 end
endmodule
module tb_scaler;
wire done;
scaler_case #(.SW(640),.SH(360),.PACE(16),.PIXEL_PERIOD(192),.ROWS(3)) prefix(done);
initial begin wait(done);$finish;end
initial begin #10000000;$fatal(1,"scaler timeout");end
endmodule
