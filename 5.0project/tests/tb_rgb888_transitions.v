`timescale 1ns/1ps
module tb_rgb888_transitions;
reg clk=0;always #5 clk=~clk;
reg rst=1,req=0;reg [2:0] effect=0;reg right=0;reg [10:0] offset=0;
wire ack,finish,en;wire [20:0] address;
frame_fifo_read #(.BURST_SIZE(256),.FRAME_WIDTH(640)) reader(.rst(rst),.mem_clk(clk),
 .Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),.Sdr_rd_en(1'b0),.App_wr_busy(1'b0),
 .App_rd_en(en),.App_rd_addr(address),.read_req(req),.read_req_ack(ack),.read_finish(finish),
 .read_addr_0(21'd0),.read_addr_1(21'd691200),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd3840),
 .slide_active(1'b1),.slide_old_index(2'd0),.slide_new_index(2'd1),.slide_offset(offset),.slide_right(right),.transition_mode(effect),
 .buffer0_vga(1'b0),.buffer1_vga(1'b0),.wrusedw(9'd0));
// Oracle is expressed in physical pixel coordinates. Packed words never
// cross a four-pixel source group, even at a burst or effect boundary.
function integer expected_address;
 input integer word_x,yy,shift,fx,direction;
 integer pixel_x,move,source_x,split,pattern,limit;reg use_new;
 begin
  pixel_x=(word_x/3)*4;move=(shift/2)*4;split=1280-move;source_x=pixel_x;use_new=0;
  case(fx)
   0:if(direction==0)begin use_new=pixel_x>=split;source_x=use_new ? pixel_x-split:pixel_x+move;end
     else begin use_new=pixel_x<move;source_x=use_new ? pixel_x+split:pixel_x-move;end
   1:use_new=pixel_x>=640-(move/4)*2 && pixel_x<640+(move/4)*2;
   2:use_new=(yy%90)<((shift/2*2>>3)+(shift/2*2>>6));
   3:use_new=(direction ? 639-pixel_x/2+yy:pixel_x/2+yy)<((shift/2*2)*2+(shift/2*2)/2);
   4:begin
    pattern=(((pixel_x>>10)^(yy>>9))&1)*8+(((pixel_x>>9)^(yy>>8))&1)*4+(((pixel_x>>8)^(yy>>7))&1)*2+(((pixel_x>>7)^(yy>>6))&1);
    use_new=(direction ? 15-pattern:pattern)<(shift/2*2>>5);
   end
   5:use_new=move>=640;
  endcase
  expected_address=(use_new ? 691200:0)+yy*960+(source_x/4)*3+word_x%3;
 end
endfunction
integer n=0,checks=0,e,d,s,g,yy,phase,word_x,exp;reg checking=0;
always @(posedge clk)if(en && checking)begin
 exp=expected_address(n%960,n/960,offset,effect,right);
 if(address!==exp)$fatal(1,"RGB888 reader effect=%0d direction=%0d shift=%0d word=%0d got=%0d expected=%0d",effect,right,offset,n,address,exp);
 n=n+1;checks=checks+1;
end
// Direct boundary sweep also checks last row and full-frame endpoints.
reg [10:0] mx=0;reg [9:0] my=0;reg [1:0] mp=0;wire [20:0] ma;
reg [20:0] ob=0,nb=691200;
saixian_frame_mapper mapper(.word_phase(mp),.xpos(mx),.ypos(my),.old_base(ob),.new_base(nb),
 .enabled(1'b1),.move_right(right),.effect(effect),.offset({offset[10:1],1'b0}),.address(ma));
initial begin
 for(e=0;e<6;e=e+1)for(d=0;d<2;d=d+1)begin
  effect=e;right=d;
  for(s=0;s<=640;s=s+40)begin
   offset=s;
   for(yy=0;yy<720;yy=yy+89)for(g=0;g<320;g=g+1)for(phase=0;phase<3;phase=phase+1)begin
    mx=g*2;my=yy;mp=phase;ob=yy*960;nb=691200+yy*960;#1;
    exp=expected_address(g*3+phase,yy,s,e,d);
    if(ma!==exp)$fatal(1,"RGB888 mapper e=%0d d=%0d step=%0d x=%0d y=%0d phase=%0d got=%0d expected=%0d",e,d,s,g,yy,phase,ma,exp);
    checks=checks+1;
   end
  end
  // Actual read FSM: unaligned 256-word bursts across 960-word rows.
  for(s=0;s<3;s=s+1)begin
   @(negedge clk);rst=1;offset=s==0 ? 11'd7:s==1 ? 11'd320:11'd640;checking=0;
   repeat(5)@(negedge clk);rst=0;repeat(5)@(negedge clk);n=0;req=1;checking=1;
   wait(ack);@(negedge clk);req=0;wait(!ack);wait(finish);@(negedge clk);
   checking=0;if(n!=3840)$fatal(1,"RGB888 frame length got %0d",n);
  end
 end
 $display("PASS RGB888 all six effects/both directions: %0d addresses, packed-group phases, row and burst boundaries",checks);$finish;
end
initial begin #100000000;$fatal(1,"RGB888 transition timeout");end
endmodule
