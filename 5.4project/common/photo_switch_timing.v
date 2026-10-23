`timescale 1ns/1ps
// Observer only. One millisecond resolution, saturating at 99999 ms.
// Results publish together on successful finish and survive a cancelled run.
module photo_switch_timing #(parameter CLK_HZ=75000000,PHASES=2)(
 input clk,rst,start,mark1,mark2,finish,cancel,
 output reg running,valid,output reg [19:0] first_ms,second_ms,third_ms,total_ms
);
localparam MS_CYCLES=CLK_HZ/1000;
localparam DIV_BITS=(MS_CYCLES<2) ? 1:$clog2(MS_CYCLES);
reg [DIV_BITS-1:0] divider;
reg [1:0] phase;
reg [19:0] elapsed,stage_time,first_hold,second_hold;
wire tick=divider==MS_CYCLES-1;
function [19:0] increment_bcd;
 input [19:0] value;
 begin
  increment_bcd=value;
  if(value!=20'h99999)begin
   if(value[3:0]!=9)increment_bcd[3:0]=value[3:0]+1'b1;
   else begin
    increment_bcd[3:0]=0;
    if(value[7:4]!=9)increment_bcd[7:4]=value[7:4]+1'b1;
    else begin
     increment_bcd[7:4]=0;
     if(value[11:8]!=9)increment_bcd[11:8]=value[11:8]+1'b1;
     else begin
      increment_bcd[11:8]=0;
      if(value[15:12]!=9)increment_bcd[15:12]=value[15:12]+1'b1;
      else begin increment_bcd[15:12]=0;increment_bcd[19:16]=value[19:16]+1'b1;end
     end
    end
   end
  end
 end
endfunction
wire [19:0] elapsed_now=tick ? increment_bcd(elapsed):elapsed;
wire [19:0] stage_now=tick ? increment_bcd(stage_time):stage_time;
always @(posedge clk or posedge rst)begin
 if(rst)begin
  running<=0;valid<=0;divider<=0;phase<=0;elapsed<=0;stage_time<=0;
  first_hold<=0;second_hold<=0;first_ms<=0;second_ms<=0;third_ms<=0;total_ms<=0;
 end else if(cancel)begin running<=0;end
 else if(start)begin
  running<=1;divider<=0;phase<=0;elapsed<=0;stage_time<=0;first_hold<=0;second_hold<=0;
 end else if(running)begin
  divider<=tick ? 0:divider+1'b1;
  elapsed<=elapsed_now;stage_time<=stage_now;
  if(phase==0 && mark1)begin first_hold<=elapsed_now;stage_time<=0;phase<=1;end
  if(PHASES==3 && phase==1 && mark2)begin second_hold<=stage_now;stage_time<=0;phase<=2;end
  if(finish && ((PHASES==2 && phase==1) || (PHASES==3 && phase==2)))begin
   first_ms<=first_hold;second_ms<=PHASES==2 ? stage_now:second_hold;
   third_ms<=PHASES==3 ? stage_now:20'd0;total_ms<=elapsed_now;
   valid<=1;running<=0;
  end
 end
end
endmodule

// Digit order matches photo_status: index 0 is the page, 1..5 are decimal ms.
// A decimal point on the page means another measurement is in progress.
module photo_switch_timing_display #(parameter CLK_HZ=75000000,PAGES=3)(
 input clk,rst,running,input [19:0] first_ms,second_ms,third_ms,total_ms,
 output reg [5:0] seg_sel,output reg [7:0] seg_data
);
localparam SCAN_DIV=CLK_HZ/6000;
localparam SCAN_BITS=(SCAN_DIV<2) ? 1:$clog2(SCAN_DIV);
localparam PAGE_BITS=$clog2(CLK_HZ*2);
reg [SCAN_BITS-1:0] scan_count;
reg [PAGE_BITS-1:0] page_count;
reg [2:0] index;
reg [1:0] page;
reg [23:0] digits;
reg page_running;
reg [19:0] selected_ms;
reg [3:0] digit;
function [7:0] glyph;
 input [3:0] value;
 begin case(value)
  0:glyph=8'hc0;1:glyph=8'hf9;2:glyph=8'ha4;3:glyph=8'hb0;4:glyph=8'h99;
  5:glyph=8'h92;6:glyph=8'h82;7:glyph=8'hf8;8:glyph=8'h80;9:glyph=8'h90;
  default:glyph=8'hbf;
 endcase end
endfunction
always @*begin
 case(page)
  0:selected_ms=first_ms;
  1:selected_ms=second_ms;
  2:selected_ms=PAGES==3 ? total_ms:third_ms;
  default:selected_ms=total_ms;
 endcase
end
always @(posedge clk or posedge rst)begin
 if(rst)begin scan_count<=0;page_count<=0;index<=0;page<=0;digits<=0;page_running<=0;end
 else begin
  if(page_count==CLK_HZ*2-1)begin page_count<=0;page<=page==PAGES-1 ? 0:page+1'b1;end
  else page_count<=page_count+1'b1;
  if(scan_count==SCAN_DIV-1)begin
   scan_count<=0;index<=index==5 ? 0:index+1'b1;
   if(index==5)begin
    digits<={selected_ms[3:0],selected_ms[7:4],selected_ms[11:8],selected_ms[15:12],selected_ms[19:16],1'b0,({1'b0,page}+3'd1)};
    page_running<=running;
   end
  end else scan_count<=scan_count+1'b1;
 end
end
always @*begin
 digit=digits>>(index*4);seg_data=glyph(digit);
 if(index==0 && page_running)seg_data[7]=0;
 seg_sel=6'b111111 ^ (6'b000001<<index);
end
endmodule
