`timescale 1ns/1ps
module tb_result_raster;
reg clk=0;always #5 clk=~clk;
reg rst=1,di=0,vi=0;reg [23:0] ri=0;
reg [10:0] x=0;reg [9:0] y=0;
wire busy,sprint,de,vs;wire [23:0] rgb;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(1'b0),.trigger(1'b0),
 .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.x_in(x),.y_in(y),
 .de_in(di),.vs_in(vi),.rgb_in(ri),.sprint_background_valid(1'b1),
 .busy(busy),.sprint_active(sprint),.de_out(de),.vs_out(vs),.rgb_out(rgb));
reg [7:0] dq=0,vq=0;reg [23:0] rq[0:7];
integer k,n,v;reg signed [12:0] value;
always @(posedge clk) begin
 if(rst) begin dq=0;vq=0;for(k=0;k<8;k=k+1) rq[k]=0;end
 else begin
  dq={dq[6:0],di};vq={vq[6:0],vi};
  for(k=7;k>0;k=k-1) rq[k]=rq[k-1];rq[0]=di?ri:0;
 end
 for(v=0;v<1024;v=v+1) begin
  value=v-322;
  if(((value[12:7]==0)&&!(value[6]&&value[5]))!==((v>=322)&&(v<418)))
   $fatal(1,"direct raster title bound not equivalent");
 end
 #1;
 if({de,vs,rgb}!=={dq[7],vq[7],rq[7]}) $fatal(1,"result raster RGB/DE/VS misaligned");
end
initial begin
 for(v=-4096;v<4096;v=v+1) begin
  value=v;
  if(((value>=0)&&(value<384))!==((value[12:9]==0)&&!(value[8]&&value[7]))) $fatal(1,"384 bound not equivalent");
  if(((value>=0)&&(value<96))!==((value[12:7]==0)&&!(value[6]&&value[5]))) $fatal(1,"96 bound not equivalent");
 end
 repeat(3) @(negedge clk);rst=0;
 for(n=0;n<4096;n=n+1) begin
  @(negedge clk);di=(n%19<15);vi=(n%997<5);ri=n*24'h010203;x=n%1280;y=(n/1280);
 end
 di=0;repeat(7) @(negedge clk);
 $display("PASS 4096 full-speed raster pixels and exhaustive signed title-bound equivalence");$finish;
end
endmodule
