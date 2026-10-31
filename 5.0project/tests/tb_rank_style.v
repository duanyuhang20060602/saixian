`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,tick=0,we=0,de=0,capture=0;
reg [5:0] wi=0;reg [31:0] wd=0;reg [10:0] x=0;reg [9:0] y=0;
reg [3:0] mode=5;reg [7:0] phase=95;wire [23:0] rgb,original;wire out_de,old_de;
saixian_battle_result_fx dut(.clk(clk),.rst(rst),.frame_tick(tick),.trigger(1'b0),.select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),
 .x_in(x),.y_in(y),.de_in(de),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b0),.busy(),.sprint_active(),.de_out(out_de),.vs_out(),.rgb_out(rgb),
 .rank_word_valid(we),.rank_word_row(3'd0),.rank_word_index(wi),.rank_word_data(wd),.rank_word_length(4'd2),.rank_word_score(16'h1234));
before_battle ref_fx(.clk(clk),.rst(rst),.frame_tick(tick),.trigger(1'b0),.select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),
 .x_in(x),.y_in(y),.de_in(de),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b0),.busy(),.sprint_active(),.de_out(old_de),.vs_out(),.rgb_out(original));
reg [31:0] updates[0:15];reg [10:0] qx[0:7];reg [9:0] qy[0:7];reg [7:0] qc=0;
integer i,j,fd,pixels=0,fixed_pixels=0,score_pixels=0;reg [1023:0] output_path;
reg body,edited_column;integer virtual_x,row_offset,source_y,source_x;
reg [3:0] digit;reg [31:0] reference_word;reg [1:0] reference_alpha;reg [23:0] expected_color;
function [7:0] blend;input [7:0] base;input [1:0] a;begin case(a)
0:blend=base;1:blend=(base>>1)+(base>>2)+63;2:blend=(base>>2)+191;3:blend=255;endcase end endfunction
reg [31:0] atlas[0:8191];reg [1:0] expected_small[0:2351];
always @(posedge clk)begin
 qx[0]<=x;qy[0]<=y;qc<={qc[6:0],capture};
 for(j=1;j<8;j=j+1)begin qx[j]<=qx[j-1];qy[j]<=qy[j-1];end
 #1;
 if(!rst && qc[7])begin
  if(!out_de || old_de!==out_de)$fatal(1,"video sideband latency changed");
  if($isunknown(rgb))$fatal(1,"uninitialized style pixel");
  $fwrite(fd,"%06x\n",rgb);pixels=pixels+1;
  body=(qy[7]>=180 && qy[7]<276)||(qy[7]>=315 && qy[7]<411)||(qy[7]>=450 && qy[7]<546);
  edited_column=body && qx[7]>=328 && qx[7]<668;
  if(!edited_column)begin
   if(rgb!==original)$fatal(1,"fixed rank/lane/unit/background changed x=%0d y=%0d rgb=%h old=%h",qx[7],qy[7],rgb,original);
   fixed_pixels=fixed_pixels+1;
  end
  // Compare the first edited score against the original digit atlas glyphs,
  // using the original 13,13,5,13,13 advances and original gold panel color.
  if(qy[7]>=214 && qy[7]<242 && qx[7]>=584 && qx[7]<668)begin
   virtual_x=qx[7]-584;row_offset=qy[7]-214;
   reference_alpha=expected_small[row_offset*84+virtual_x];
   expected_color={blend(8'h18,reference_alpha),blend(8'h2d,reference_alpha),blend(8'h3a,reference_alpha)};
   // The time inset's original color is palette 28 (0x182d3a).
   if(rgb!==expected_color)$fatal(1,"score font/style mismatch at %0d,%0d got=%h wanted=%h",qx[7],qy[7],rgb,expected_color);
   score_pixels=score_pixels+1;
  end
 end
end
initial begin
 if(!$value$plusargs("out=%s",output_path))output_path="rank-style-frame.hex";fd=$fopen(output_path,"w");
 $readmemh("tests/rank_style_expected_score.hex",expected_small);$readmemh("tests/rank_style_update.hex",updates);$readmemh("src/board_a/user_source/hdl_source/saixian_sprint_atlas.hex",atlas);
 repeat(5)@(negedge clk);rst=0;force dut.state=mode;force ref_fx.state=mode;force dut.result_frame=phase;force ref_fx.result_frame=phase;
 for(i=0;i<16;i=i+1)begin wi=i;wd=updates[i];we=1;@(negedge clk);we=0;repeat(2)@(negedge clk);end
 tick=1;@(negedge clk);tick=0;repeat(20)@(negedge clk);
 if(dut.editable_ranking.enabled!==255 || dut.editable_ranking.scores[{3'd0,dut.editable_ranking.banks[0]}]!=16'h1234)$fatal(1,"rank defaults or replacement missing");
 capture=1;de=1;
 for(i=0;i<720;i=i+1)begin y=i;for(integer xx=0;xx<1280;xx=xx+1)begin x=xx;@(negedge clk);end end
 de=0;capture=0;repeat(12)@(negedge clk);$fclose(fd);
 if(pixels!=921600 || score_pixels!=2352 || fixed_pixels<800000)$fatal(1,"incomplete frame checks");
 $display("PASS full-frame style: %0d pixels, %0d exact fixed rank/lane/unit/background pixels, %0d smaller antialiased score/unit pixels",pixels,fixed_pixels,score_pixels);$finish;
end
initial begin #20000000;$fatal(1,"timeout");end
endmodule
