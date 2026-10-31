`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,we=0;
reg [5:0] wi=0;reg [10:0] x=0;reg [9:0] y=0;reg de=0;wire [23:0] rgb;wire out_de;
reg [3:0] mode=3;reg [7:0] phase=143;integer i,j,checks=0;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(tick),.trigger(1'b0),.select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),
 .x_in(x),.y_in(y),.de_in(de),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b0),.busy(),.sprint_active(),.de_out(out_de),.vs_out(),.rgb_out(rgb),
 .rank_word_valid(we),.rank_word_row(3'd0),.rank_word_index(wi),.rank_word_data(32'hffffffff),.rank_word_length(4'd1),.rank_word_score(16'h1234));
reg [7:0] expected=0,valid=0;
wire expected_ink=mode==3 ? (x>=164 && x<196 && y>=151 && y<183):(x>=184 && x<216 && y>=214 && y<246);
always @(posedge clk)begin
 expected<={expected[6:0],expected_ink};valid<={valid[6:0],de};
 #1;if(!rst && valid[7])begin
  if(out_de!==1 || (rgb==24'hffffff)!==expected[7])$fatal(1,"rank/podium glyph latency or clipping wrong mode=%0d rgb=%h expected white=%b",mode,rgb,expected[7]);
  checks=checks+1;
 end
end
initial begin
 repeat(5)@(negedge clk);rst=0;
 force dut.state=mode;force dut.result_frame=phase;
 for(j=0;j<8;j=j+1)begin wi=j;we=1;@(negedge clk);we=0;repeat(2)@(negedge clk);end
 tick=1;@(negedge clk);tick=0;repeat(15)@(negedge clk);
 for(j=0;j<2;j=j+1)begin
  if(j==1)begin de=0;repeat(12)@(negedge clk);mode=5;phase=95;tick=1;@(negedge clk);tick=0;repeat(15)@(negedge clk);end
  for(i=0;i<1600;i=i+1)begin
   de=1;x=(j==0 ? 158:178)+(i%44);y=(j==0 ? 147:210)+((i/44)%40);@(negedge clk);
  end
 end
 de=0;repeat(12)@(negedge clk);
 if(checks<3000)$fatal;
 $display("PASS %0d rank/podium pixels: named glyph dimensions, clipping and unchanged 8-clock RGB/DE alignment",checks);$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
