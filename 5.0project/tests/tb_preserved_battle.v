`timescale 1ns/1ps
// Preserve exact colors/priority/latency when moving geometry predicates to
// the existing coordinate stage. Reference is the untouched pre-change RTL.
module tb_v4_battle_equivalence;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,de=0,vs=0,bg=0;reg [10:0] x=0;reg [9:0] y=0;reg [23:0] rgb=0;
reg [3:0] mode=0;reg [8:0] phase=0;reg [7:0] result_phase=0;reg redside=0;
wire [23:0] actual,golden;wire ad,av,gd,gv;
integer checks=0,case_id,i,frame_id;reg [31:0] random_state=32'hf16a934b;
integer phases[0:15];integer modes[0:8];
saixian_battle_result_fx dut(.rank_word_valid(1'b0),.clk(clk),.rst(rst),.frame_tick(tick),.trigger(1'b0),
 .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),.x_in(x),.y_in(y),.de_in(de),.vs_in(vs),.rgb_in(rgb),
 .sprint_background_valid(bg),.busy(),.sprint_active(),.de_out(ad),.vs_out(av),.rgb_out(actual));
before_battle ref_fx(.clk(clk),.rst(rst),.frame_tick(tick),.trigger(1'b0),
 .select_blue(1'b0),.select_red(1'b0),.select_sprint(1'b0),.stop(1'b0),.x_in(x),.y_in(y),.de_in(de),.vs_in(vs),.rgb_in(rgb),
 .sprint_background_valid(bg),.busy(),.sprint_active(),.de_out(gd),.vs_out(gv),.rgb_out(golden));
always @(posedge clk)if(!rst)begin
 #1;if(ad!==gd || av!==gv || actual!==golden)$fatal(1,"retimed scene changed case=%d phase=%d x=%d y=%d got=%h ref=%h",case_id,phase,x,y,actual,golden);
 if(ad)begin if($isunknown(actual))$fatal(1,"undefined scene pixel");checks=checks+1;end
end
initial begin
 phases[0]=0;phases[1]=49;phases[2]=50;phases[3]=64;phases[4]=65;phases[5]=77;phases[6]=78;phases[7]=107;
 phases[8]=108;phases[9]=129;phases[10]=130;phases[11]=155;phases[12]=156;phases[13]=215;phases[14]=216;phases[15]=255;
 modes[0]=0;modes[1]=1;modes[2]=2;modes[3]=7;modes[4]=8;modes[5]=3;modes[6]=4;modes[7]=5;modes[8]=6;
 repeat(6)@(negedge clk);rst=0;
 force dut.state=mode;force ref_fx.state=mode;force dut.frame_count=phase;force ref_fx.frame_count=phase;
 force dut.result_frame=result_phase;force ref_fx.result_frame=result_phase;force dut.red_selected=redside;force ref_fx.red_selected=redside;
 for(case_id=0;case_id<9;case_id=case_id+1)begin
  mode=modes[case_id];redside=(mode==7 || mode==8);
  for(frame_id=0;frame_id<16;frame_id=frame_id+1)begin
   phase=phases[frame_id];result_phase=phase;bg=frame_id[0];tick=1;repeat(2)@(negedge clk);tick=0;
   for(i=0;i<2048;i=i+1)begin
    @(negedge clk);random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    x=random_state[15:0]%1280;y=random_state[31:16]%720;rgb=random_state[23:0];de=i%17!=0;vs=i%127==0;
   end
  end
 end
 de=0;repeat(20)@(negedge clk);
 $display("PASS victory geometry retiming: %d exact RGB pixels, 9 scene states/16 boundary phases, blue/red, rank/podium, background/fallback and unchanged DE/VS latency",checks);$finish;
end
initial begin #5000000;$fatal(1,"scene comparison timeout");end
endmodule
