`timescale 1ns/1ps
module tb_thumbnail_memory;
reg clk=0,vc=0,rst=1;
always #10 clk=~clk;
always #7 vc=~vc;
reg color=0,allow_access=1,other=0,blocked=0,frame_busy=0;
reg job=0,cancel=0,blank=1;reg [1:0] slot=0;
reg [12:0] va=0;wire [15:0] vd;wire done,request,claim,rd;wire [20:0] address;
integer cycles=0,reads=0,i;
wire refresh=(cycles%401)<7;
reg [9:0] responses=0;reg [31:0] pipe[0:9];
photo_thumbnail_memory dut(.clk(clk),.rst(rst),.init_done(1'b1),.refresh(refresh),
 .busy(blocked),.frame_busy(frame_busy),.allow_access(allow_access),.other_request(other),
 .request(request),.claim(claim),.read_command(rd),.address(address),.response_valid(responses[9]),.response(pipe[9]),
 .video_clk(vc),.video_request(job),.video_cancel(cancel),.video_blank(blank),.video_slot(slot),.video_done(done),.video_address(va),.video_data(vd));
function [23:0] pixel;
 input integer x,y,s;
 begin pixel={(x[7:0]^8'had^s[7:0]),(y[7:0]^8'h73),(x[7:0]+y[7:0]+s[7:0])};end
endfunction
function [15:0] ref565;
 input integer x,y,s;reg [23:0] p;
 begin p=pixel(x,y,s);ref565={p[23:19],p[15:10],p[7:3]};end
endfunction
function [31:0] source;
 input [20:0] a;integer s,w,x,y;reg [23:0] p0,p1,p2,p3;
 begin
  s=a/1048576;w=a%1048576;
  if(1'b0)begin
   y=w/960;x=(w%960)/3*4;
   p0=pixel(x,y,s);p1=pixel(x+1,y,s);p2=pixel(x+2,y,s);p3=pixel(x+3,y,s);
   case(w%3)0:source={p0,p1[23:16]};1:source={p1[15:0],p2[23:8]};2:source={p2[7:0],p3};endcase
  end else begin y=w/640;x=(w%640)*2;source={ref565(x,y,s),ref565(x+1,y,s)};end
 end
endfunction
reg previous_claim=0;
always @(posedge clk)begin
 cycles<=cycles+1;previous_claim<=claim;
 responses<={responses[8:0],rd};
 if(rd)begin
  if(address>=2097152)$fatal(1,"read outside photo slots %d",address);
  if(!claim || refresh)$fatal(1,"unowned or refresh command");
  pipe[0]<=source(address);reads<=reads+1;
 end
 for(i=1;i<10;i=i+1)pipe[i]<=pipe[i-1];
 if(!previous_claim && claim && (!allow_access || other || blocked || frame_busy || !dut.blank_sync || dut.cancel_sync))
  $fatal(1,"access admitted while forbidden");
end
task start;
 input [1:0] s;input c;
 begin @(negedge vc);slot=s;color=c;cancel=0;job=~job;end
endtask
task finish_check;
 input integer s;integer x,y,before_reads;
 begin
  wait(done==job);repeat(4)@(negedge vc);
  for(y=0;y<63;y=y+1)for(x=0;x<112;x=x+1)begin
   @(negedge vc);va=y*112+x;@(negedge vc);
   if(vd!==ref565((x*80+40)/7,(y*80+40)/7,s))$fatal(1,"cache s=%d color=%d y=%d x=%d got=%h expected=%h",s,color,y,x,vd,ref565((x*80+40)/7,(y*80+40)/7,s));
  end
  before_reads=reads;repeat(100)@(negedge clk);
  if(reads!=before_reads)$fatal(1,"completed preview still reads SDRAM");
  $display("PASS static eRAM cache: slot=%0d color=%0d, all 7056 pixels including bank boundary, no hold-time SDRAM traffic",s,color);
 end
endtask
integer before_reads;
initial begin
 repeat(8)@(negedge clk);rst=0;
 blank=0;start(0,0);repeat(100)@(negedge clk);if(claim || request)$fatal(1,"active video arbitration");
 blank=1;allow_access=0;repeat(100)@(negedge clk);if(claim || request)$fatal(1,"display FIFO reserve ignored");
 allow_access=1;other=1;repeat(100)@(negedge clk);if(claim || request)$fatal(1,"award priority ignored");
 other=0;blocked=1;repeat(100)@(negedge clk);if(claim)$fatal(1,"SDRAM busy ignored");
 blocked=0;frame_busy=1;repeat(100)@(negedge clk);if(claim)$fatal(1,"frame owner ignored");
 frame_busy=0;before_reads=reads;finish_check(0);if(reads-before_reads!=40320)$fatal(1,"unexpected complete read count");
 start(1,0);before_reads=reads;wait(reads>=before_reads+128);
 @(negedge vc);blank=0;repeat(100)@(negedge clk);
 if(claim)$fatal(1,"in-flight turn did not drain after vertical blank");
 before_reads=reads;repeat(100)@(negedge clk);
 if(reads!=before_reads)$fatal(1,"sampling continued in active video");
 blank=1;finish_check(1);start(1,0);finish_check(1);
 start(0,0);wait(rd);@(negedge vc);cancel=1;
 wait(done==job);if(claim)$fatal(1,"cancellation acknowledged before bus release");
 repeat(5)@(negedge vc);start(1,0);finish_check(1);
 start(1,0);wait(dut.row==32 && dut.column==5 && rd);
 @(negedge vc);cancel=1;wait(done==job);repeat(5)@(negedge vc);
 start(0,0);finish_check(0);
 $display("PASS whole-cache CDC, RGB565, both native 4MiB slots, refresh, priority, cancellation and restart");$finish;
end
initial begin #100000000;$fatal(1,"memory timeout reads=%d",reads);end
endmodule
