`timescale 1ns/1ps
module hdmi_scan_monitor #(
 parameter integer HT=2200,VT=1125,HA=1920,VA=1080,HS=44,VS=5
)(input wire clk,input wire rst,input wire [11:0] x,input wire [10:0] y,
 input wire de,input wire hs,input wire vs,input wire frame_start,
 output reg valid,output reg fault);
 reg started,line_started;
 reg [21:0] frame_cycles,active_pixels,vs_cycles;
 reg [11:0] line_cycles,line_active;
 reg [7:0] line_hs;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   valid<=0;fault<=0;started<=0;line_started<=0;
   frame_cycles<=0;active_pixels<=0;vs_cycles<=0;
   line_cycles<=0;line_active<=0;line_hs<=0;
  end else begin
   if(x==0) begin
    if(line_started && (line_cycles!=HT || line_hs!=HS ||
       (line_active!=0 && line_active!=HA))) fault<=1;
    line_started<=1;line_cycles<=1;line_active<=de;line_hs<=hs;
   end else begin
    line_cycles<=line_cycles+1'b1;
    if(de) line_active<=line_active+1'b1;
    if(hs) line_hs<=line_hs+1'b1;
   end
   if(frame_start) begin
    if(started) begin
     valid<=1;
     if(frame_cycles!=HT*VT || active_pixels!=HA*VA || vs_cycles!=HT*VS) fault<=1;
    end
    started<=1;frame_cycles<=1;active_pixels<=de;vs_cycles<=vs;
   end else if(started) begin
    frame_cycles<=frame_cycles+1'b1;
    if(de) active_pixels<=active_pixels+1'b1;
    if(vs) vs_cycles<=vs_cycles+1'b1;
   end
  end
 end
endmodule

module hdmi_pixel_clock_monitor #(
 parameter integer WINDOW_REF_CYCLES=5000000,
 parameter integer EXPECTED_PIXELS=7425000,
 parameter integer TOLERANCE_PIXELS=74250
)(input wire ref_clk,input wire pixel_clk,input wire arst,
 output reg valid,output reg fault);
 // Registered Gray bus, sampled through two flops in the reference domain.
 // New samples are separated by 100 ms, far below the 27-bit wrap interval.
 reg [26:0] pixel_count,pixel_gray;
 always @(posedge pixel_clk or posedge arst) begin
  if(arst) begin pixel_count<=0;pixel_gray<=0;end
  else begin pixel_count<=pixel_count+1'b1;
   pixel_gray<=((pixel_count+27'd1)>>1)^(pixel_count+27'd1);
  end
 end
 (* ASYNC_REG="TRUE" *) reg [26:0] gray_meta,gray_sync;
 reg [26:0] previous_sample;
 reg [22:0] window_count;
 reg have_sample;
 wire [26:0] binary_sample;
 genvar k;
 generate for(k=0;k<27;k=k+1) begin:g_gray
  assign binary_sample[k]=^gray_sync[26:k];
 end endgenerate
 wire [26:0] delta=binary_sample-previous_sample;
 always @(posedge ref_clk or posedge arst) begin
  if(arst) begin gray_meta<=0;gray_sync<=0;previous_sample<=0;
   window_count<=0;have_sample<=0;valid<=0;fault<=0;end
  else begin
   gray_meta<=pixel_gray;gray_sync<=gray_meta;
   if(window_count==WINDOW_REF_CYCLES-1) begin
    window_count<=0;previous_sample<=binary_sample;have_sample<=1;
    if(have_sample) begin
     valid<=1;
     if(delta<EXPECTED_PIXELS-TOLERANCE_PIXELS || delta>EXPECTED_PIXELS+TOLERANCE_PIXELS) fault<=1;
    end
   end else window_count<=window_count+1'b1;
  end
 end
endmodule
