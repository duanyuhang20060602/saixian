`timescale 1ns/1ps
module tb_pointer_overlay;
reg clk=0;always #5 clk=~clk;
reg rst=1,frame=0,enable=1,de=0;reg [11:0] x=0;reg [10:0] y=0;
wire [23:0] rgb;reg [23:0] expected[0:25];integer i,t;
reg [10:0] cx=640;reg [9:0] cy=360;reg visible=0;
reg body,border,button,ink;integer dx,dy;
photo_pointer_overlay dut(.clk(clk),.rst(rst),.frame_tick(frame),.enable(enable),.navigation_enable(1'b0),.de(de),.x(x),.y(y),
 .cursor_x(cx),.cursor_y(cy),.rgb_in(24'h345678),.rgb_out(rgb));
always @(posedge clk)begin
 if(rst)begin for(i=0;i<26;i=i+1)expected[i]=24'h345678;visible=0;end
 else begin
  for(i=25;i>0;i=i-1)expected[i]=expected[i-1];
  dx=x-cx;dy=y-cy;
  body=visible && de && dx>=0 && dy>=0 && dx<16 && dy<24 && dx*2<=dy+2;
  border=body && (dx<2 || dy>21 || dx*2>=dy);
  button=visible && de && x>=1152 && x<1256 && y>=24 && y<64;
  ink=x>=1180 && x<1228 && ((y>=34 && y<38)||(y>=44 && y<48)||(y>=54 && y<58));
  expected[0]=body ? (border ? 24'h101820:24'hffffff):button ? (ink ? 24'hffffff:24'h205f7a):24'h345678;
  if(frame)visible=enable;
  #1;if(rgb!==expected[25])$fatal(1,"26 clock cursor alignment at %d,%d got %h expected %h",x,y,rgb,expected[25]);
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;frame=1;@(negedge clk);frame=0;
 // Cursor bounds, menu launcher, blanking and disable transitions.
 for(t=0;t<10000;t=t+1)begin
  @(negedge clk);de=(t%101)!=0;
  x=t<5000 ? 620+t%40:1140+t%130;y=t<5000 ? 350+(t/40)%45:15+(t/130)%60;
  if(t==7000)begin frame=1;enable=0;end else frame=0;
 end
 repeat(30)@(negedge clk);
 $display("PASS pointer raster shape, clipping, DE, visibility and exact 26-clock alignment");$finish;
end
endmodule
