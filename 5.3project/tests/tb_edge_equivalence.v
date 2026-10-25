`timescale 1ns/1ps
module tb_edge_equivalence;
reg clk=0,rst=1;always #5 clk=~clk;
reg [10:0] x=0;reg [9:0] y=0;reg [31:0] noise=32'h1b73fa97;
wire de=x<1280 && y<720;
wire ft=x==0;
wire [23:0] a,b,c;wire [7:0] la,lb,lc;wire da,db,sa,sb,ea,eb,dc,sc,ec;
integer i;
water_edge_reference reference(.clk(clk),.rst(rst),.frame_tick(ft),.music_drive(noise[0]),.pcm_valid(noise[1]),
 .pcm_left(noise[31:16]),.pcm_right(noise[15:0]),.x(x),.y(y),.de(de),.sof(x==0 && y==0),.eol(x==1279),
 .rgb(noise[23:0]),.darkness(noise[29:24]),.de_out(da),.sof_out(sa),.eol_out(ea),.rgb_out(a),.level(la));
water_edge candidate(.clk(clk),.rst(rst),.frame_tick(ft),.music_drive(noise[0]),.pcm_valid(noise[1]),
 .pcm_left(noise[31:16]),.pcm_right(noise[15:0]),.x(x),.y(y),.de(de),.sof(x==0 && y==0),.eol(x==1279),
 .rgb(noise[23:0]),.darkness(noise[29:24]),.de_out(db),.sof_out(sb),.eol_out(eb),.rgb_out(b),.level(lb));
water_edge #(.EXTERNAL_ENVELOPE(1)) external_candidate(.clk(clk),.rst(rst),.frame_tick(ft),.music_drive(noise[0]),.pcm_valid(1'b0),
 .pcm_left(16'd0),.pcm_right(16'd0),.external_target(reference.target),.x(x),.y(y),.de(de),.sof(x==0 && y==0),.eol(x==1279),
 .rgb(noise[23:0]),.darkness(noise[29:24]),.de_out(dc),.sof_out(sc),.eol_out(ec),.rgb_out(c),.level(lc));
initial begin
 repeat(8)@(negedge clk);rst=0;
 for(i=0;i<2097152;i=i+1)begin
  @(negedge clk);x=i%2048;y=i/2048;
  noise={noise[30:0],noise[31]^noise[21]^noise[1]^noise[0]};
  @(posedge clk);#1;
  if(i>20 && {a,da,sa,ea,la}!=={b,db,sb,eb,lb})$fatal(1,"edge equivalence x=%d y=%d a=%h b=%h",x,y,a,b);
  if(i>20 && {a,da,sa,ea,la}!=={c,dc,sc,ec,lc})$fatal(1,"external envelope changed RGB/latency at x=%d y=%d",x,y);
 end
 $display("PASS edge eRAM equivalence: all 2097152 coordinate pairs, random RGB/audio/darkness, identical RGB/DE/SOF/EOL/level and latency");$finish;
end
endmodule
