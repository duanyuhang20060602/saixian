`timescale 1ns/1ps
module tb;
reg clk=0,mc=0;always #6.667 clk=~clk;always #10 mc=~mc;
reg rst=1,enable=0,mode=0,pause=0,touch=0,de=0,tick=0;
reg[10:0]x=0,cursor_x=640;reg[9:0]y=720,cursor_y=360;reg[23:0]pixel=0;
wire[20:0]base=mode ? 21'd262144:21'd0;
wire request,ref_request;wire[20:0]address,ref_address;reg ack=0,valid=0;reg[31:0]data=0;
wire[23:0]rgb,menu,ref_rgb,ref_menu;wire[3:0]error,ref_error;wire[6:0]frame,ref_frame;
photo_award_render #(.RELIEF_ENABLE(1),.SHARED_ENABLE(1)) dut(
 .relief_mode(mode),.touch_contact(touch),.cursor_x(cursor_x),.cursor_y(cursor_y),
 .mem_clk(mc),.mem_rst(rst),.light_base(base),.light_request(request),.light_address(address),.light_ack(ack),.light_data(data),.light_valid(valid),
 .de_in(de),.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.tagged_rgb(pixel),.rgb(rgb),.menu_rgb(menu),.light_error(error),.light_frame(frame));
photo_award_render #(.RELIEF_ENABLE(1),.SHARED_ENABLE(0)) reference(
 .relief_mode(mode),.touch_contact(touch),.cursor_x(cursor_x),.cursor_y(cursor_y),
 .mem_clk(mc),.mem_rst(rst),.light_base(base),.light_request(ref_request),.light_address(ref_address),.light_ack(ack),.light_data(data),.light_valid(valid),
 .de_in(de),.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.tagged_rgb(pixel),.rgb(ref_rgb),.menu_rgb(ref_menu),.light_error(ref_error),.light_frame(ref_frame));
defparam dut.gold.player.HOLD_FRAMES=2;
defparam reference.gold.player.HOLD_FRAMES=2;
reg[31:0]legacy[0:230399],relief[0:230399];reg[15:0]background[0:921599];
integer ms=0,waits=0,lane=0,transactions=0;reg[20:0]latched;
always @(posedge mc)begin
 ack<=0;valid<=0;
 if(rst)begin ms<=0;transactions<=0;end
 else begin
  if(request!==ref_request || (request && address!==ref_address))$fatal(1,"cache sharing changed memory requests");
  case(ms)
  0:if(request)begin
   if(!((address<230400)||(address>=262144 && address<492544)) || address[1:0]!=0)$fatal(1,"memory request bounds");
   latched<=address;waits<=transactions%17+5;transactions<=transactions+1;ms<=1;
  end
  1:if(waits==0)begin ack<=1;lane<=0;ms<=2;end else waits<=waits-1;
  2:begin
   data<=latched>=262144 ? relief[latched-262144+lane]:legacy[latched+lane];valid<=1;lane<=lane+1;
   if(lane==3)begin ms<=3;waits<=12;end
  end
  3:if(waits==0)ms<=0;else waits<=waits-1;
  endcase
 end
end
integer checks=0,pixels=0,segments=0;reg visible_window=0;
always @(posedge clk)if(!rst)begin
 #1;
 if(rgb!==ref_rgb || menu!==ref_menu || error!==ref_error || frame!==ref_frame)
  $fatal(1,"shared cache changed renderer mode=%0d x=%0d y=%0d actual=%h reference=%h error=%h/%h",mode,x,y,rgb,ref_rgb,error,ref_error);
 checks=checks+1;
 if(de && visible_window)begin
  if(error!==0)$fatal(1,"shared cache underflow mode=%0d error=%0d",mode,error);
  pixels=pixels+1;
 end
end
function[23:0] expand;input[15:0]p;begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
integer xx,yy,f;
task line;input integer row;begin
 for(xx=0;xx<1650;xx=xx+1)begin
  @(negedge clk);x=xx;y=row;de=xx<1280 && row<720;tick=xx==0 && row==720;
  pixel=de && mode ? expand(background[row*1280+xx]):24'h706030;
 end
end endtask
task show;input new_mode;begin
 @(negedge clk);mode=new_mode;pause=0;touch=0;visible_window=0;
 for(yy=720;yy<750;yy=yy+1)line(yy);
 for(f=0;f<2;f=f+1)begin
  visible_window=1;pause=new_mode && f==1;touch=new_mode && f==1;
  for(yy=0;yy<750;yy=yy+1)begin cursor_x=(yy*7)%1280;cursor_y=(yy*3)%720;line(yy);end
 end
 visible_window=0;segments=segments+1;
end endtask
initial begin
 $readmemh("legacy_tail.hex",legacy);$readmemh("relief_tail.hex",relief);$readmemh("relief_base.hex",background);
 repeat(8)@(negedge clk);rst=0;enable=1;
 show(0);show(1);show(0);repeat(60)@(negedge clk);
 if(pixels!=5529600 || segments!=3 || transactions<1000)$fatal(1,"incomplete cache sharing coverage pixels=%0d",pixels);
 $display("PASS shared award cache: old-new-old, 6 full 720p frames, %0d visible pixels, %0d same-cycle RGB/menu/control comparisons, %0d stalled four-word bursts, pause and touch, zero underflow",pixels,checks,transactions);$finish;
end
initial begin #500000000;$fatal(1,"shared cache timeout");end
endmodule
