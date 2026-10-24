`timescale 1ns/1ps
module tb_mapper;
reg [10:0] x=0,offset=0;reg [9:0] y=0;reg right=0;reg [2:0] effect=0;
wire [20:0] addr;reg [20:0] old_base,new_base;
saixian_frame_mapper #(.FRAME_WIDTH(640)) dut(.word_phase(2'd0),.xpos(x),.ypos(y),.old_base(old_base),.new_base(new_base),.enabled(1'b1),.move_right(right),.effect(effect),.offset(offset),.address(addr));
integer yy,xx,step,e,d,split,column,expected,checks=0,bl,pattern;reg use_new;
initial begin
 for(d=0;d<2;d=d+1)for(e=0;e<6;e=e+1)for(step=0;step<=640;step=step+31)
 for(yy=0;yy<720;yy=yy+1)for(xx=0;xx<640;xx=xx+37)begin
  x=xx;y=yy;right=d;effect=e;offset=step;old_base=yy*640;new_base=921600+yy*640;#1;
  use_new=0;column=xx;split=640-step;
  case(e)
   0:begin
    if(d==0)begin use_new=xx>=split;column=use_new ? xx-split:xx+step;end
    else begin use_new=xx<step;column=use_new ? xx+split:xx-step;end
   end
   1:use_new=xx>=(320-step/2) && xx<(320+step/2);
   2:begin bl=yy%90;use_new=bl<((step>>3)+(step>>6));end
   3:use_new=(d ? 639-xx+yy:xx+yy)<((step<<1)+(step>>1));
   4:begin pattern=(((xx>>9)^(yy>>9))&1)*8+(((xx>>8)^(yy>>8))&1)*4+(((xx>>7)^(yy>>7))&1)*2+(((xx>>6)^(yy>>6))&1);
     use_new=(d ? (15-pattern):pattern)<(step>>5);end
   5:use_new=step>=320;
  endcase
  expected=(use_new ? new_base:old_base)+column;
  if(addr!==expected || column<0 || column>=640)$fatal(1,"transition address e=%d x=%d y=%d offset=%d got=%d expected=%d",e,xx,yy,step,addr,expected);
  checks=checks+1;
 end
 // Odd word widths must still complete every effect at the full endpoint.
 for(e=0;e<6;e=e+1)begin effect=e;offset=640;x=639;y=719;old_base=719*640;new_base=921600+719*640;#1;
  if(addr!=new_base+639)$fatal(1,"last-column transition endpoint e=%d",e);
 end
 $display("PASS %d independent transition address checks, 640-word rows and 720-line boundaries",checks);$finish;
end
endmodule
