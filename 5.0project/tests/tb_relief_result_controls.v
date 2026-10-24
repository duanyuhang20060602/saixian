`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,carousel=1,settings=0,award=0,loading=0;
reg[3:0] presses=0;reg[5:0] commands=0;reg keylong=0;
wire[2:0] direct_raw;
wire command_blue=commands[0],command_red=commands[1],command_sprint=commands[2],command_next=commands[3],command_stop=commands[4];
wire trigger_raw,stop_raw;
top_photo_a dut(.clk(clk),.key(4'hf),.hmi_uart_rx(1'b1));
initial begin
 force dut.pixel_clk=clk;force dut.rst_pixel=rst;
 force dut.carousel_mode=carousel;force dut.settings_mode=settings;
 force dut.award_active=award;force dut.award_loading=loading;
 force dut.presses=presses;force dut.key4_long=keylong;
 force dut.hmi_result_blue=command_blue;force dut.hmi_result_red=command_red;force dut.hmi_result_sprint=command_sprint;
 force dut.hmi_next=command_next;force dut.hmi_result_stop=command_stop;
 force dut.raster_tick26=tick;force dut.raster_x26=12'd0;force dut.raster_y26=11'd720;
 force dut.raster_de26=1'b0;force dut.raster_vs26=1'b0;force dut.feature_rgb=24'd0;force dut.display_valid=1'b1;
end
assign direct_raw[0]=(commands[0] || (dut.result_busy && presses[1])) && carousel && !settings && !award && !loading;
assign direct_raw[1]=(commands[1] || (dut.result_busy && presses[2])) && carousel && !settings && !award && !loading;
assign direct_raw[2]=(commands[2] || keylong) && carousel && !settings && !award && !loading;
assign trigger_raw=(dut.result_busy && carousel && !settings) && (presses[0] || commands[3]);
assign stop_raw=commands[4] || (keylong && dut.result_busy);
// Reference consumes the same qualified top events before the new register.
// The busy feedback reception window itself deliberately settles one clk later.
reference_result_fx reference(.clk(clk),.rst(rst),.frame_tick(tick),.trigger(trigger_raw),
 .select_blue(direct_raw[0]),.select_red(direct_raw[1]),.select_sprint(direct_raw[2]),.stop(stop_raw),
 .x_in(11'd0),.y_in(10'd720),.de_in(1'b0),.vs_in(1'b0),.rgb_in(24'd0),.sprint_background_valid(1'b1),
 .busy(),.sprint_active(),.de_out(),.vs_out(),.rgb_out());
wire[70:0] state_actual={dut.u_result_animation.state,dut.u_result_animation.pending,dut.u_result_animation.stop_pending,
 dut.u_result_animation.direct_pending,dut.u_result_animation.auto_podium,dut.u_result_animation.red_selected,
 dut.u_result_animation.frame_count,dut.u_result_animation.result_frame,dut.u_result_animation.wipe_edge,
 dut.u_result_animation.sheen_edge,dut.u_result_animation.title_drop,dut.u_result_animation.gold_line_edge};
wire[70:0] state_reference={reference.state,reference.pending,reference.stop_pending,reference.direct_pending,reference.auto_podium,
 reference.red_selected,reference.frame_count,reference.result_frame,reference.wipe_edge,reference.sheen_edge,
 reference.title_drop,reference.gold_line_edge};
reg[70:0] previous;reg[5:0] sampled;reg armed=0;integer checks=0,stops=0;
always @(posedge clk)begin
 sampled={tick,stop_raw,trigger_raw,direct_raw};
 #1;
 if(rst)begin previous=state_reference;armed=1;end
 else if(armed)begin
  if(state_actual!==previous)$fatal(1,"qualified control trace shifted incorrectly cycle=%0d got=%h expected=%h",checks,state_actual,previous);
  if({dut.result_frame_tick_q,dut.result_stop_q,dut.result_trigger_q,dut.result_select_sprint_q,dut.result_select_red_q,dut.result_select_blue_q}!==sampled)
   $fatal(1,"production top command gate/register mismatch");
  previous=state_reference;checks=checks+1;
 end
end
integer i,j,mask;reg[31:0] rng=32'h86ef13b5;
task clear;begin @(negedge clk);commands=0;presses=0;keylong=0;tick=0;end endtask
task clock_frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;repeat(3)@(negedge clk);end endtask
task reset;begin rst=1;commands=0;presses=0;keylong=0;tick=0;repeat(3)@(negedge clk);rst=0;repeat(3)@(negedge clk);end endtask
initial begin
 reset();
 // Explicit regression for simultaneous select/stop/frame: no deferred restart.
 for(i=1;i<8;i=i+1)begin
  @(negedge clk);commands={1'b0,1'b1,1'b1,i[2:0]};tick=1;
  clear();repeat(3)@(negedge clk);clock_frame();clock_frame();
  if(dut.result_busy || dut.u_result_animation.state!=0)$fatal(1,"stop+select priority caused unexpected restart");stops=stops+1;
 end
 // All three choices plus trigger use blue priority and consume pending.
 @(negedge clk);commands=1;clock_frame();clear();repeat(4)@(negedge clk);
 @(negedge clk);commands=6'b001111;tick=1;clear();repeat(4)@(negedge clk);
 if(dut.u_result_animation.state!=1 || dut.u_result_animation.pending || dut.u_result_animation.direct_pending)
  $fatal(1,"direct blue/red/sprint + trigger priority changed");
 // A pending stop followed by select+trigger at a frame boundary consumes both.
 @(negedge clk);commands=6'b010000;clear();
 @(negedge clk);commands=6'b001100;tick=1;clear();repeat(3)@(negedge clk);clock_frame();
 if(dut.result_busy || dut.u_result_animation.direct_pending)$fatal(1,"pending stop lost priority over direct/trigger choice");
 // Every gate combination, all three direct commands and button sources.
 for(mask=0;mask<16;mask=mask+1)begin
  @(negedge clk);carousel=!mask[0];settings=mask[1];award=mask[2];loading=mask[3];
  for(j=1;j<8;j=j+1)begin @(negedge clk);commands=j;presses=j;tick=1;clear();repeat(4)@(negedge clk);end
 end
 @(negedge clk);carousel=1;settings=0;award=0;loading=0;
 // Real direct entry then K4 stop/sprint collision keeps stop priority.
 commands=1;clock_frame();clear();repeat(4)@(negedge clk);
 if(!dut.result_busy)$fatal(1,"direct blue did not enter result");
 @(negedge clk);keylong=1;tick=1;clear();repeat(4)@(negedge clk);clock_frame();
 if(dut.result_busy)$fatal(1,"K4 while result busy must stop without restarting sprint");
 for(i=0;i<12000;i=i+1)begin
  @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  commands=rng[5:0] & {6{rng[9:8]==0}};presses=rng[13:10]&{4{rng[15:14]==0}};
  keylong=rng[23:16]==8'h45;tick=i%23==0;
  carousel=rng[26:25]!=0;settings=rng[28:27]==0;award=rng[30:29]==0;loading=rng[7:6]==0;
 end
 clear();repeat(8)@(negedge clk);
 if(checks<12000)$fatal(1,"incomplete trace");
 $display("PASS production top result controls: exact one-clock qualified FSM trace cycles=%0d, 16 gate masks, stop/select/trigger/frame priorities, pending stop and K4 no restart checks=%0d",checks,stops);$finish;
end
initial begin #1000000;$fatal(1,"result-control timeout");end
endmodule
