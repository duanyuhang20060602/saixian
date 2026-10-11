`timescale 1ns/1ps
// Production memory arbiter, native FIFOs, 75MHz raster; modeled SDRAM.
module tb_spotlight_bus;
reg mc=0,vc=0;always #10 mc=~mc;always #6.666667 vc=~vc;
reg rst=1;
reg [31:0] memory[0:809599],ram[0:2097151];
integer file_words,i,j,cycle=0,refresh_clock=0,refresh_left=0,refreshes=0;
string package_path;
wire req,pop,ack,valid,initialized;wire [20:0] offset,length;
wire [31:0] data;wire [3:0] error,bus_error;wire [6:0] index;
wire rd,wr,rd_valid;wire [20:0] ra,wa;wire [31:0] wd,rd_data;
reg [9:0] pending=0;reg [31:0] response[0:9];
reg refreshing=0,refresh_pending=0;
wire busy=rd || wr || |pending;
assign rd_valid=pending[9];assign rd_data=response[9];
wire inhibit_refresh=refreshing || (refresh_pending && bus.state==0 && !busy);
wire vreset,vpush,stream_reset,cmd_push;wire [31:0] vdata,vhead,cmd_data;
wire [8:0] vcount,cmd_count;wire vempty,vfull,cmd_empty,cache_ready;
wire frame,visible,active,underflow,vpop,commit;wire [23:0] rgb,out;wire de,vs,ode,ovs;
reg [2:0] fs=0;reg dm=0,ds=0,am=0,aslot=0;
always @(posedge mc)begin
 if(rst)begin pending<=0;fs<=0;dm<=0;ds<=0;am<=0;aslot<=0;end
 else begin
  cycle<=cycle+1;fs<={fs[1:0],frame};dm<=visible;ds<=dm;am<=active;aslot<=am;
  pending<={pending[8:0],rd};if(rd)response[0]<=ram[ra];
  for(i=1;i<10;i=i+1)response[i]<=response[i-1];
  if(rd && refreshing)$fatal(1,"read during refresh");
  if(wr)$fatal(1,"unexpected write after preload");
  if(vpush && vfull)$fatal(1,"video FIFO overflow");
  if(bus_error || error || underflow)$fatal(1,"bus/light/video fault %d/%d/%d at %t",bus_error,error,underflow,$time);
  refresh_clock<=refresh_clock+1;
  if(refresh_clock==389)begin refresh_pending<=1;refresh_clock<=0;end
  if(refresh_pending && bus.state==0 && !busy)begin refreshing<=1;refresh_left<=8;refresh_pending<=0;refreshes<=refreshes+1;end
  else if(refreshing)begin refresh_left<=refresh_left-1;if(refresh_left==1)refreshing<=0;end
 end
end
delta_memory #(.FRAME_WORDS(460800)) bus(mc,rst,1'b1,inhibit_refresh,busy,rd,ra,rd_valid,rd_data,wr,wa,wd,
 1'b1,21'd0,1'b1,9'd0,32'd0,,cache_ready,fs[2],ds,aslot,vreset,vpush,vdata,vcount,
 req,offset,length,ack,stream_reset,cmd_push,cmd_data,cmd_count,
 1'b0,21'd0,32'd0,,bus_error,,32'd0,,,);
wfifo_32_32_512 command_fifo(.rst(rst|stream_reset),.clkw(mc),.clkr(mc),.we(cmd_push),.di(cmd_data),.re(pop),.dout(data),
 .empty_flag(cmd_empty),.full_flag(),.rdusedw(cmd_count),.wrusedw(),.valid(),.afull(),.aempty());
assign valid=!cmd_empty;
rfifo_32_32_512 #(.SHOW_AHEAD_EN(1'b1)) video_fifo(.rst(rst|vreset),.clkw(mc),.clkr(vc),.we(vpush),.di(vdata),.re(vpop),.dout(vhead),
 .full_flag(vfull),.empty_flag(vempty),.wrusedw(vcount),.rdusedw(),.valid(),.afull(),.aempty());
delta_video #(.SCENE_WIDTH(1280),.SCENE_HEIGHT(720)) scan(vc,rst,1'b1,1'b0,vhead,vempty,vpop,rgb,de,vs,commit,frame,active,visible,underflow,1'b0);
spotlight_player #(.INITIAL_HOLD_FRAMES(0)) dut(mc,rst,cache_ready,file_words[20:0],req,offset,length,ack,data,valid,pop,error,
 vc,rst,visible,1'b0,rgb,de,vs,out,ode,ovs,index,initialized);
function [7:0] lit;
 input [7:0] c,t,a;integer product;
 begin product=(t>c ? t-c : 0)*a;lit=c+(product/256);end
endfunction
function [7:0] map_byte;
 input integer frame_id,x,y;reg [31:0] w;integer n;
 begin n=y*160+x;w=memory[memory[memory[65]+frame_id*4]+n/4];map_byte=w>>((n%4)*8);end
endfunction
function integer threshold;
 input integer x,y;
 begin threshold=((x%2)^(y%2))*128+(y%2)*64+(((x/2)%2)^((y/2)%2))*32+((y/2)%2)*16+8;end
endfunction
function [7:0] spatial;
 input integer frame_id,x,y;integer lx,rx,uy,ly,fx,fy,top,bottom;
 begin
  lx=x<4?0:(x-4)/8;uy=y<4?0:(y-4)/8;
  if(lx>159)lx=159;if(uy>89)uy=89;rx=lx<159?lx+1:lx;ly=uy<89?uy+1:uy;
  fx=x<4?0:(x-4)%8;fy=y<4?0:(y-4)%8;
  top=map_byte(frame_id,lx,uy)*(8-fx)+map_byte(frame_id,rx,uy)*fx;
  bottom=map_byte(frame_id,lx,ly)*(8-fx)+map_byte(frame_id,rx,ly)*fx;
  spatial=(top*(8-fy)+bottom*fy+threshold(x,y)/4)/64;
 end
endfunction

reg [23:0] expected[0:6];reg [6:0] expected_de=0,expected_vs=0;
reg previous_de=0;integer px=0,py=0,checks=0,frames_checked=0,frame_samples=0,oracle_frame=0,oracle_phase=0;
reg [7:0] alpha;
integer request_cycle=0,max_latency=0,line_jobs=0;
always @(posedge vc)begin
 if(!rst)begin
  if(dut.request_pending && request_cycle==0)request_cycle=cycle;
  if(!dut.request_pending && request_cycle!=0)begin
   if(cycle-request_cycle>max_latency)max_latency=cycle-request_cycle;
   request_cycle=0;line_jobs=line_jobs+1;
  end
  expected[6]=expected[5];expected[5]=expected[4];expected[4]=expected[3];expected[3]=expected[2];expected[2]=expected[1];expected[1]=expected[0];
  alpha=0;
  if(de && initialized && dut.next_ready && visible && py<548)begin
   alpha=(spatial(index,px,py)*(256-(dut.step*256+1)/3)+spatial((index+1)%120,px,py)*((dut.step*256+1)/3)+threshold(px,py))/256;
  end
  expected[0]={lit(rgb[23:16],255,alpha),lit(rgb[15:8],235,alpha),lit(rgb[7:0],200,alpha)};
  expected_de={expected_de[5:0],de};expected_vs={expected_vs[5:0],vs};
  if(vs)py=0;else if(previous_de && !de)py=py+1;
  if(de)px=px+1;else px=0;previous_de=de;
  #1;
  if(ode!==expected_de[6] || ovs!==expected_vs[6])$fatal(1,"bus RGB/DE/VS alignment");
  if(ode && initialized && visible)begin
   if(out!==expected[6])$fatal(1,"bus pixel differs %h != %h x=%d y=%d",out,expected[6],px,py);
   checks=checks+1;frame_samples=frame_samples+1;
   if(frame_samples==921600)begin
    frame_samples=0;frames_checked=frames_checked+1;
    $display("complete raster %0d index=%0d phase=%0d refreshes=%0d max_job=%0d clocks",frames_checked,index,dut.step,refreshes,max_latency);$fflush();
    if(index!=(frames_checked-1)/3 || dut.step!=(frames_checked-1)%3)$fatal(1,"temporal sequence differs");
    if(frames_checked==4)begin
     if(line_jobs<250 || refreshes<100)$fatal(1,"insufficient arbitration stress");
     $display("PASS rolling SDRAM: %0d exact RGB pixels, 4 complete 720p scans including temporal interpolation and frame switch, %0d refreshes, %0d row jobs, max job %0d mem clocks; zero HDMI FIFO underflows",checks,refreshes,line_jobs,max_latency);$finish;
    end
   end
  end
 end
end
initial begin
 if(!$value$plusargs("package=%s",package_path)||!$value$plusargs("words=%d",file_words))$fatal;
 $readmemh(package_path,memory,0,file_words-1);
 for(j=0;j<file_words;j=j+1)ram[921600+j]=memory[j];
 for(j=0;j<921600;j=j+1)ram[j]=32'h50385038;
 for(j=0;j<7;j=j+1)expected[j]=0;
 repeat(8)@(negedge mc);rst=0;
end
initial begin #250000000;$fatal(1,"bus test timeout");end
endmodule
