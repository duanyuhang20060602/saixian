`timescale 1ns/1ps
module tb_picture_stream;
reg clk=0; always #5 clk=~clk;
reg rst=1, de=0;
reg [10:0] x=0;
reg [23:0] rgb=0;
reg [3:0] b=4,c=4,s=4;
wire [23:0] out;
saixian_picture_adjust_pipe dut(clk,rst,de,x,rgb,b,c,s,2'd0,out);
reg [23:0] expected[0:7];
reg [10:0] xpos[0:7];
reg [7:0] dep=0;
integer i,n,ib,ic,is,cycles=0,checked=0;
function integer scale;
 input integer v,level; input sat;
 begin
  case(level)
   0:scale=sat?0:(v>>>1);
   1:scale=sat?(v>>>2):((v>>>1)+(v>>>3));
   2:scale=sat?(v>>>1):((v>>>1)+(v>>>2));
   3:scale=sat?(v-(v>>>2)):(v-(v>>>3));
   4:scale=v; 5:scale=v+(v>>>3); 6:scale=v+(v>>>2);
   7:scale=v+(v>>>1); default:scale=v+(v>>>1)+(v>>>2);
  endcase
 end
endfunction
function integer clamp;
 input integer v;
 begin clamp=v<0?0:(v>255?255:v); end
endfunction
function [23:0] reference;
 input [23:0] pixel; input integer br,co,sa;
 integer r,g,bl,y,offset;
 begin
  offset=br<9?(br-4)*16:64;
  r=clamp(scale(pixel[23:16]-128,co,0)+128+offset);
  g=clamp(scale(pixel[15:8]-128,co,0)+128+offset);
  bl=clamp(scale(pixel[7:0]-128,co,0)+128+offset);
  y=(r+2*g+bl)>>2;
  r=clamp(y+scale(r-y,sa,1));
  g=clamp(y+scale(g-y,sa,1));
  bl=clamp(y+scale(bl-y,sa,1));
  reference={r[7:0],g[7:0],bl[7:0]};
 end
endfunction
always @(posedge clk) begin
 if(rst) begin
  cycles=0; dep=0;
  for(i=0;i<8;i=i+1) begin expected[i]=0;xpos[i]=0;end
 end else begin
  for(i=7;i>0;i=i-1) begin expected[i]=expected[i-1];xpos[i]=xpos[i-1];end
  expected[0]=reference(rgb,b,c,s); xpos[0]=x;
  dep={dep[6:0],de}; cycles=cycles+1;
  #1;
  // Skip the blanking interval after changing frame-stable controls.
  if(cycles>=8 && dep[7]) begin
   if(out!==expected[7]) $fatal(1,"8-cycle RGB alignment x=%d got=%h expected=%h",xpos[7],out,expected[7]);
   checked=checked+1;
  end
 end
end
initial begin
 repeat(4) @(negedge clk);rst=0;
 for(ib=0;ib<9;ib=ib+1) for(ic=0;ic<9;ic=ic+1) for(is=0;is<9;is=is+1) begin
  de=0;b=ib;c=ic;s=is;repeat(12) @(negedge clk);
  for(n=0;n<64;n=n+1) begin
   de=1;x=n;rgb={8'(n*4),8'(n*57),8'(n*101)};
   @(negedge clk);
  end
  de=0;repeat(12) @(negedge clk);
 end
 if(checked!=46656) $fatal(1,"lost pixels %d",checked);
 $display("PASS 46656 consecutive pixels, 8-stage latency, all 9x9x9 settings");$finish;
end
initial begin #10000000;$fatal(1,"timeout");end
endmodule
