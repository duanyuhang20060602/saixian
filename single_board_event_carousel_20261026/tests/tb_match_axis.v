`timescale 1ns/1ps
module tb_match_axis;
reg clk=0;always #5 clk=~clk;
reg rst=1,ft=0,de=0,vs=0;reg [10:0] x=0;reg [9:0] y=0;
wire [23:0] rgb;wire od,ov;
match_render d(clk,rst,ft,de,vs,x,y,3'd2,3'd0,3'd1,10'd27,10'd14,9'd10,2'd0,2'd0,rgb,od,ov,
 2'd0,1'b0,3'd0,3'd1,10'd0,10'd0,7'd1,1'b0);
wire user,valid,last;wire [23:0] data;
video_rgb_to_axis_640x480 #(.H_ACTIVE(1280)) axis(clk,rst,ov,od,rgb,user,valid,last,data);
integer row,col,pixels=0,lines=0,starts=0,line_pixels=0;
reg [23:0] accepted_rgb;
always @(posedge clk)begin
 accepted_rgb=rgb;
 #1;
 if(!rst)begin
  if(valid)begin
   if(data!==accepted_rgb)$fatal(1,"RGB pipeline mismatch");
   pixels=pixels+1;line_pixels=line_pixels+1;
   if(user)begin starts=starts+1;if(pixels!=1)$fatal(1,"SOF misplaced");end
   if(last)begin if(line_pixels!=1280)$fatal(1,"EOL at %d",line_pixels);lines=lines+1;line_pixels=0;end
  end else if(last || user)$fatal(1,"sideband outside valid");
 end
end
initial begin
 repeat(4)@(negedge clk);rst=0;ft=1;@(negedge clk);ft=0;
 for(row=0;row<750;row=row+1)for(col=0;col<1650;col=col+1)begin
  @(negedge clk);x=col;y=row;de=col<1280 && row<720;vs=row>=725 && row<730;
 end
 @(negedge clk);de=0;vs=0;repeat(10)@(negedge clk);
 if(pixels!=921600 || lines!=720 || starts!=1)$fatal(1,"AXIS totals pixels=%d lines=%d SOF=%d",pixels,lines,starts);
 $display("PASS HDMI input: 921600 RGB pixels, 720 EOLs, one SOF, exact data alignment");$finish;
end
endmodule
