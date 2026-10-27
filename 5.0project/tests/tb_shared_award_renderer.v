`timescale 1ns/1ps
module tb;
reg clk=0,mc=0;always #6.667 clk=~clk;always #10 mc=~mc;
reg rst=1,enable=0,mode=0,pause=0,touch=0,de=0,tick=0;
reg[10:0]x=0,cursor_x=640;reg[9:0]y=720,cursor_y=360;reg[23:0]pixel=0;
reg sent=0,begin_packet=0,word_valid=0,finish_packet=0,commit_packet=0;
reg[8:0]word_index=0;reg[31:0]word_data=0,sent_descriptor=0;
wire[31:0]descriptor,ref_descriptor;wire available,ref_available;
wire wall_we,ref_wall_we;wire[7:0]wall_wa,wall_ra,ref_wall_wa,ref_wall_ra;wire[23:0]wall_wd,ref_wall_wd;
reg[23:0]wall_rgb,ref_wall_rgb;reg[23:0]wall_ram[0:255];reg[31:0]palette[0:255],wall_codes[0:127];
function[23:0]unpack_wall;input[16:0]v;reg[7:0]r,g,b;begin r=v[16:9];g=(r>>1)+v[8:4];b=(r>>3)+v[3:0];unpack_wall={r,g,b};end endfunction
always @(posedge clk)begin
 if(wall_we)wall_ram[wall_wa]<=unpack_wall(wall_wd[16:0]);
 wall_rgb<=wall_ram[wall_ra];ref_wall_rgb<=wall_ram[ref_wall_ra];
 if(!rst && ({wall_we,wall_wa,wall_wd,descriptor,available}!=={ref_wall_we,ref_wall_wa,ref_wall_wd,ref_descriptor,ref_available}))$fatal(1,"shared DSP changed table/control access");
 if(!rst && mode && dut.remote_valid && wall_ra!==ref_wall_ra)$fatal(1,"active trophy wall lookup changed");
end
wire[20:0]base=mode ? 21'd524288:21'd0;
wire request,ref_request,wide,ref_wide;wire[20:0]address,ref_address;reg ack=0,valid=0;reg[31:0]data=0;
wire[23:0]rgb,menu,ref_rgb,ref_menu;wire[3:0]error,ref_error;wire[6:0]frame,ref_frame;
photo_award_render #(.RELIEF_ENABLE(1),.REMOTE_RELIEF(1),.SHARED_MATH(1)) dut(
 .relief_sent(sent),.relief_sent_descriptor(sent_descriptor),.relief_begin(begin_packet),.relief_word_valid(word_valid),.relief_finish(finish_packet),.relief_commit(commit_packet),.relief_word_index(word_index),.relief_word(word_data),.relief_descriptor(descriptor),.relief_available(available),.wall_we(wall_we),.wall_wa(wall_wa),.wall_ra(wall_ra),.wall_wd(wall_wd),.wall_rgb(wall_rgb),.relief_mode(mode),.touch_contact(touch),.cursor_x(cursor_x),.cursor_y(cursor_y),
 .mem_clk(mc),.mem_rst(rst),.light_base(base),.light_wide(wide),.light_request(request),.light_address(address),.light_ack(ack),.light_data(data),.light_valid(valid),
 .de_in(de),.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.tagged_rgb(pixel),.rgb(rgb),.menu_rgb(menu),.light_error(error),.light_frame(frame));
photo_award_render_before #(.RELIEF_ENABLE(1),.REMOTE_RELIEF(1)) reference(
 .relief_sent(sent),.relief_sent_descriptor(sent_descriptor),.relief_begin(begin_packet),.relief_word_valid(word_valid),.relief_finish(finish_packet),.relief_commit(commit_packet),.relief_word_index(word_index),.relief_word(word_data),.relief_descriptor(ref_descriptor),.relief_available(ref_available),.wall_we(ref_wall_we),.wall_wa(ref_wall_wa),.wall_ra(ref_wall_ra),.wall_wd(ref_wall_wd),.wall_rgb(ref_wall_rgb),.relief_mode(mode),.touch_contact(touch),.cursor_x(cursor_x),.cursor_y(cursor_y),
 .mem_clk(mc),.mem_rst(rst),.light_base(base),.light_wide(ref_wide),.light_request(ref_request),.light_address(ref_address),.light_ack(ack),.light_data(data),.light_valid(valid),
 .de_in(de),.clk(clk),.rst(rst),.enable(enable),.pause(pause),.frame_tick(tick),.x(x),.y(y),.tagged_rgb(pixel),.rgb(ref_rgb),.menu_rgb(ref_menu),.light_error(ref_error),.light_frame(ref_frame));
defparam dut.gold.player.HOLD_FRAMES=2;
defparam reference.gold.player.HOLD_FRAMES=2;
reg[31:0]legacy[0:230399],relief[0:524287];reg[15:0]background[0:921599];
integer ms=0,waits=0,lane=0,transactions=0,burst_words=4;reg[20:0]latched;
always @(posedge mc)begin
 ack<=0;valid<=0;
 if(rst)begin ms<=0;transactions<=0;end
 else begin
  if(wide!==ref_wide || request!==ref_request || (request && address!==ref_address))$fatal(1,"cache sharing changed memory requests");
  case(ms)
  0:if(request)begin
   if(!((address<230400)||(address>=524288 && address<1048576)) || address[1:0]!=0)$fatal(1,"memory request bounds");
   latched<=address;burst_words<=wide ? 64:4;waits<=transactions%17+5;transactions<=transactions+1;ms<=1;
  end
  1:if(waits==0)begin ack<=1;lane<=0;ms<=2;end else waits<=waits-1;
  2:begin
   data<=latched>=524288 ? relief[latched-524288+lane]:legacy[latched+lane];valid<=1;lane<=lane+1;
   if(lane==burst_words-1)begin ms<=3;waits<=12;end
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
  if(mode && dut.remote_valid && error!==0)$fatal(1,"shared cache underflow mode=%0d error=%0d",mode,error);
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
task send_table;integer i;begin
 repeat(30)@(negedge clk);if(!available)$fatal(1,"table unavailable on scene entry");
 sent_descriptor=descriptor;sent=1;@(negedge clk);sent=0;begin_packet=1;@(negedge clk);begin_packet=0;
 for(i=0;i<385;i=i+1)begin
  word_index=i;word_data=i==0 ? sent_descriptor:(i<=256 ? palette[i-1]:wall_codes[i-257]);word_valid=1;
  @(negedge clk);word_valid=0;repeat(14)@(negedge clk);
 end
 finish_packet=1;commit_packet=1;@(negedge clk);finish_packet=0;commit_packet=0;
 repeat(3)@(negedge clk);
 if(dut.remote_tables.control.rejected)$fatal(1,"production table rejected");
end endtask
task show;input new_mode;input integer lines;begin
 @(negedge clk);mode=new_mode;pause=1;touch=0;visible_window=0;tick=0;de=0;x=0;y=720;
 if(new_mode)send_table;
 for(yy=720;yy<750;yy=yy+1)line(yy);
 if(new_mode && !dut.remote_valid)$fatal(1,"table did not commit before visible scanout");
 visible_window=1;
 for(yy=0;yy<lines;yy=yy+1)line(yy);
 visible_window=0;segments=segments+1;
end endtask
initial begin
 $readmemh("legacy_tail.hex",legacy);$readmemh("relief_tail.hex",relief);$readmemh("relief_base.hex",background);
 $readmemh("lit_palettes.hex",palette);$readmemh("packed_wall.hex",wall_codes);
 repeat(8)@(negedge clk);rst=0;enable=1;
 show(0,80);show(1,720);show(0,80);show(1,80);de=0;tick=0;repeat(60)@(negedge clk);
 if(pixels!=1228800 || segments!=4 || transactions<1000)$fatal(1,"incomplete cache sharing coverage pixels=%0d",pixels);
 $display("PASS shared award DSPs: foil-trophy-foil-trophy, one full 720p trophy frame plus 240 transition rows, %0d visible pixels, %0d same-cycle RGB/menu/control comparisons, %0d stalled four-word bursts, atomic table commits, fixed light and pause, zero trophy underflow",pixels,checks,transactions);$finish;
end
initial begin #500000000;$fatal(1,"shared cache timeout");end
endmodule
