`timescale 1ns/1ps
module tb;
reg clk=0,mc=0;always #6.667 clk=~clk;always #5 mc=~mc;
reg rst=1,enable=0,tick=0,de=0;reg[10:0] x=0;reg[9:0] y=720;
reg[23:0] rgb=0;wire[23:0] result;wire[3:0] error;wire[4:0] angle;
wire request,wide;wire[20:0] address;reg ack=0,valid=0;reg[31:0] data=0;
reg[31:0] tail[0:524287];reg[15:0] background[0:921599];reg[23:0] golden[0:1843199];
integer mstate=0,waits=0,lane=0,transactions=0,burst_words=4;reg[20:0] latched;
photo_relief_player #(.HOLD_FRAMES(2)) dut(.mem_clk(mc),.mem_rst(rst),.enable(enable),.base(21'd1024),
 .wide_request(wide),.request(request),.address(address),.ack(ack),.data(data),.valid(valid),
 .clk(clk),.rst(rst),.pause(1'b0),.frame_tick(tick),.de(de),.x(x),.y(y),.rgb_in(rgb),
 .touch_contact(1'b0),.cursor_x(11'd640),.cursor_y(10'd360),.rgb_out(result),.error(error),.angle(angle));
always @(posedge mc)begin
 ack<=0;valid<=0;
 if(rst)begin mstate<=0;transactions<=0;end
 else case(mstate)
 0:if(request)begin
  if(address<1024 || address>=1024+524288 || address[1:0]!=0)$fatal(1,"memory bounds/alignment");
  latched<=address-1024;burst_words<=wide ? 64:4;waits<=transactions%31+5;mstate<=1;transactions<=transactions+1;
 end
 1:if(waits==0)begin ack<=1;lane<=0;mstate<=2;end else waits<=waits-1;
 2:begin data<=tail[latched+lane];valid<=1;lane<=lane+1;if(lane==burst_words-1)begin mstate<=3;waits<=12;end end
 3:if(waits==0)mstate<=0;else waits<=waits-1;
 endcase
end
reg[11:0] compare_valid=0;reg[23:0] expected[0:11];integer j,checks=0;integer visible_frame=-1;
always @(posedge clk)begin
 if(rst)compare_valid<=0;
 else begin
  compare_valid<={compare_valid[10:0],de && visible_frame>=0};
  if(de && visible_frame>=0)expected[0]<=golden[visible_frame*921600+y*1280+x];
  for(j=1;j<12;j=j+1)expected[j]<=expected[j-1];
  #1;
  if(error)$fatal(1,"row underflow/control error=%0d y=%0d row=%0d pending=%0d",error,y,dut.source_row,dut.pending);
  if(compare_valid[11])begin
   checks=checks+1;
   if(result!==expected[11])$fatal(1,"pixel latency/shader mismatch frame=%0d x=%0d y=%0d actual=%h expected=%h angle=%0d",visible_frame,x,y,result,expected[11],angle);
  end
 end
end
function[23:0] expand;input[15:0] p;begin expand={p[15:11],p[15:13],p[10:5],p[10:9],p[4:0],p[4:2]};end endfunction
integer f,yy,xx,fi,ri,expected_transactions;reg [31:0] directory_entry;
task line;input integer row;begin
 for(xx=0;xx<1650;xx=xx+1)begin
  @(negedge clk);x=xx;y=row;de=xx<1280 && row<720;tick=xx==0 && row==720;
  rgb=de ? expand(background[row*1280+xx]):0;
 end
end endtask
initial begin
 $readmemh("relief_tail.hex",tail);$readmemh("relief_base.hex",background);$readmemh("relief_golden.hex",golden);
 expected_transactions=8;
 for(fi=0;fi<2;fi=fi+1)for(ri=0;ri<576;ri=ri+1)begin
  directory_entry=tail[6208+fi*576+ri];if(ri%4==0)expected_transactions=expected_transactions+1;
  if(directory_entry[31:21]!=0)expected_transactions=expected_transactions+
   (directory_entry[31:21]+directory_entry[7:0]+255)/256;
 end
 repeat(12)@(negedge clk);rst=0;enable=1;
 for(f=0;f<2;f=f+1)begin
  for(yy=720;yy<750;yy=yy+1)line(yy);
  visible_frame=f;
  for(yy=0;yy<720;yy=yy+1)line(yy);
 end
 @(negedge clk);de=0;tick=0;repeat(20)@(negedge clk);
 if(checks!=1843200 || transactions!=expected_transactions)$fatal(1,"incomplete coverage %0d/%0d",checks,transactions);
 $display("PASS two complete 720p frames: indexed angle change, exact 12-cycle shading, dual-clock row cache, randomized memory grant stalls; pixels=%0d bursts=%0d",checks,transactions);$finish;
end
initial begin #100000000;$fatal(1,"player timeout");end
endmodule
