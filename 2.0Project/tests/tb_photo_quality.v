`timescale 1ns/1ps
// Isolate spatial processing: disable tone gain, feed low-contrast 4x4 blocks
// separated by a strong luminance edge, and compare with old sharpening.
module tb_photo_quality;
reg clk=0;always #5 clk=~clk;
reg rst=1,de=0;
reg [10:0] x=0;reg [9:0] y=0;reg [23:0] rgb=0;
wire [23:0] smooth,sharp;wire sd,od;wire [10:0] sx,ox;
saixian_adaptive_enhance #(.WIDTH(64),.PHOTO_SMOOTH(1)) photo(
 .clk(clk),.rst(rst),.de(de),.vs(1'b0),.frame_tick(1'b0),.statistics_enable(1'b0),
 .x(x),.y(y),.rgb_in(rgb),.mode(2'd1),.strength(2'd1),
 .rgb_out(smooth),.de_out(sd),.x_out(sx));
saixian_adaptive_enhance #(.WIDTH(64)) original(
 .clk(clk),.rst(rst),.de(de),.vs(1'b0),.frame_tick(1'b0),.statistics_enable(1'b0),
 .x(x),.y(y),.rgb_in(rgb),.mode(2'd1),.strength(2'd1),
 .rgb_out(sharp),.de_out(od),.x_out(ox));
integer row,col,level,n=0,st=0,ot=0,sp=0,op=0,sl,ol;
function integer absolute;input integer a;begin absolute=(a<0)?-a:a;end endfunction
always @(posedge clk) begin
 #1;
 if(!rst && sd) begin
  if(!od || sx!==ox || ^smooth===1'bx) $fatal(1,"quality alignment/unknown");
  sl=smooth[23:16];ol=sharp[23:16];
  if(smooth[15:8]!==smooth[23:16] || smooth[7:0]!==smooth[23:16]) $fatal(1,"gray colour changed");
  if(sx<32 && (sl<64 || sl>72)) $fatal(1,"left region overshoot");
  if(sx>=32 && (sl<192 || sl>200)) $fatal(1,"right region overshoot");
  if(sx==32 && sl-sp<100) $fatal(1,"strong edge lost");
  if(sx>0 && sx!=32) begin st=st+absolute(sl-sp);ot=ot+absolute(ol-op);end
  sp=sl;op=ol;n=n+1;
 end
end
initial begin
 repeat(4) @(negedge clk);rst=0;
 // Neither instance receives frame_tick, so this isolates spatial filtering.
 photo.gain=0;original.gain=0;
 for(row=0;row<16;row=row+1) begin
  for(col=0;col<64;col=col+1) begin
   level=(col<32 ? 64 : 192)+(((col/4+row/4)%2)*8);
   @(negedge clk);de=1;x=col;y=row;rgb={8'(level),8'(level),8'(level)};
  end
  @(negedge clk);de=0;repeat(8) @(negedge clk);
 end
 repeat(10) @(negedge clk);
 if(n!=1024 || st>=ot) $fatal(1,"no synthetic block variation reduction %d/%d count=%d",st,ot,n);
 $display("PASS photo synthetic blocks: variation %0d vs old %0d; strong edge, no overshoot, 1024 pixels",st,ot);
 $finish;
end
endmodule
