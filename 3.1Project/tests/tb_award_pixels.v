`timescale 1ns/1ps
// Production frame_pixels + award path, registered FIFO read data. Verify
// both color formats against raster-position pixels exactly 26 clocks later.
module tb_award_pixels;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0,hc=0;reg [11:0] x=0;reg [10:0] y=720;
wire req,re,armed,underflow;reg ack=0;reg [31:0] data=0;integer pointer=0;
wire [23:0] raw,rgb;reg [10:0] x0=0,x1=0;reg [9:0] y0=0,y1=0;
frame_pixels pixels(.clk(clk),.rst(rst),.de(de),.high_color(hc),.x(x),.y(y),.image_valid(1'b1),
 .read_ack(ack),.empty(1'b0),.data(data),.read_req(req),.read_en(re),.rgb(raw),.armed(armed),.underflow(underflow));
photo_award_render render(.clk(clk),.rst(rst),.enable(1'b0),.pause(1'b0),.frame_tick(1'b0),
 .x(x1),.y(y1),.tagged_rgb(raw),.rgb(rgb));
function [15:0] word;input integer n;begin word=(n*237)^16'h8910;end endfunction
function [23:0] expanded;input integer n;reg [15:0] p;
 begin p=word(n);expanded={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end
endfunction
function [23:0] restored;input integer n;reg [15:0] p;reg [5:0] g;reg [4:0] b;
 begin p=word(n);b=p[0] ? {1'b0,p[10:7]}:{p[4:1],1'b0};g=p[0] ? {p[10:6],1'b0}:p[10:5];
 restored={p[15:11],p[15:13],g,g[5:4],b,b[4:2]};end
endfunction
function [31:0] memory_word;input integer n;integer j;reg [23:0] a,b,c,d;
 begin
  if(!hc)memory_word={word(n*2),word(n*2+1)};
  else begin
   j=(n/3)*4;a=expanded(j);b=expanded(j+1);c=expanded(j+2);d=expanded(j+3);
   case(n%3)0:memory_word={a,b[23:16]};1:memory_word={b[15:0],c[23:8]};2:memory_word={c[7:0],d};endcase
  end
 end
endfunction
reg [23:0] expected[0:25];reg [25:0] valid=0;integer i,n,checked=0,mode;
always @(posedge clk)begin
 if(rst)begin pointer<=0;ack<=0;data<=0;x0<=0;x1<=0;y0<=0;y1<=0;valid=0;end
 else begin
  ack<=req;if(req)pointer<=0;
  if(re)begin data<=memory_word(pointer);pointer<=pointer+1;end
  x0<=x[10:0];x1<=x0;y0<=y[9:0];y1<=y0;
  for(i=25;i>0;i=i-1)expected[i]=expected[i-1];expected[0]=restored(x);
  valid={valid[24:0],de};
  #1;if(valid[25])begin
   if(rgb!==expected[25])$fatal(1,"raster/FIFO/award alignment format=%0d pixel=%0d got=%h expected=%h",hc,checked,rgb,expected[25]);
   checked=checked+1;
  end
 end
end
initial begin
 for(mode=0;mode<2;mode=mode+1)begin
  rst=1;de=0;x=0;y=720;hc=mode;checked=0;
  repeat(5)@(negedge clk);rst=0;repeat(32)@(negedge clk);
  y=0;de=1;
  for(n=0;n<1280;n=n+1)begin x=n;@(negedge clk);end
  de=0;x=1280;repeat(35)@(negedge clk);
  if(checked!=1280 || underflow)$fatal(1,"raster row incomplete format=%0d count=%0d",hc,checked);
 end
 $display("PASS actual frame_pixels RGB565/RGB888 FIFO pair/phase order, first/last pixels and 26-clock HDMI raster alignment");$finish;
end
endmodule
