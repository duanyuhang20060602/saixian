`timescale 1ns/1ps
module tb_timer_equivalence;
reg clk=0;always #5 clk=~clk;
reg rst=1,prev=0,nxt=0,mode=0,award=0,transition=0,commit=0,armed=0,done=0,fault=0;
reg [18:0] settings=0;reg [31:0] crc=0;
reg got=0,tx_busy=0;reg [159:0] incoming=0;
integer i,j;reg [31:0] sample;
photo_cached_control_a #(.CLK_HZ(75000000),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.CHECK_FRAME_CRC(1)) dut(.clk(clk),.rst(rst),.uart_rx(1'b1),.previous(prev),.next(nxt),.settings_mode(mode),.settings_state(settings),.award_toggle(award),.active_slot(2'd0),.new_slot(2'd1),.transition_active(transition),.commit_toggle(commit),.rx_armed(armed),.rx_done(done),.rx_fault(fault),.rx_crc(crc));
touchscreen_timer_reference #(.CLK_HZ(75000000),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.FLUID(1),.AWARD_LIGHTS(1),.CHECK_FRAME_CRC(1)) refdut(.clk(clk),.rst(rst),.uart_rx(1'b1),.previous(prev),.next(nxt),.settings_mode(mode),.settings_state(settings),.award_toggle(award),.active_slot(2'd0),.new_slot(2'd1),.transition_active(transition),.commit_toggle(commit),.rx_armed(armed),.rx_done(done),.rx_fault(fault),.rx_crc(crc));
task compare;begin
if(dut.timer !== refdut.timer)$fatal(1,"Mismatch timer at iteration %0d",i);
if(dut.state_flags !== refdut.state_flags)$fatal(1,"Mismatch state_flags at iteration %0d",i);
if(dut.send !== refdut.send)$fatal(1,"Mismatch send at iteration %0d",i);
if(dut.message !== refdut.message)$fatal(1,"Mismatch message at iteration %0d",i);
if(dut.session !== refdut.session)$fatal(1,"Mismatch session at iteration %0d",i);
if(dut.request_seq !== refdut.request_seq)$fatal(1,"Mismatch request_seq at iteration %0d",i);
if(dut.image_count !== refdut.image_count)$fatal(1,"Mismatch image_count at iteration %0d",i);
if(dut.current_image !== refdut.current_image)$fatal(1,"Mismatch current_image at iteration %0d",i);
if(dut.cache_valid !== refdut.cache_valid)$fatal(1,"Mismatch cache_valid at iteration %0d",i);
if(dut.nav_pending !== refdut.nav_pending)$fatal(1,"Mismatch nav_pending at iteration %0d",i);
if(dut.nav_target !== refdut.nav_target)$fatal(1,"Mismatch nav_target at iteration %0d",i);
if(dut.target !== refdut.target)$fatal(1,"Mismatch target at iteration %0d",i);
if(dut.receive_slot !== refdut.receive_slot)$fatal(1,"Mismatch receive_slot at iteration %0d",i);
if(dut.arm_toggle !== refdut.arm_toggle)$fatal(1,"Mismatch arm_toggle at iteration %0d",i);
if(dut.abort_toggle !== refdut.abort_toggle)$fatal(1,"Mismatch abort_toggle at iteration %0d",i);
if(dut.error !== refdut.error)$fatal(1,"Mismatch error at iteration %0d",i);
if(dut.first_transfer_origin !== refdut.first_transfer_origin)$fatal(1,"Mismatch first_transfer_origin at iteration %0d",i);
if(dut.first_transfer_error !== refdut.first_transfer_error)$fatal(1,"Mismatch first_transfer_error at iteration %0d",i);
if(dut.applied_settings !== refdut.applied_settings)$fatal(1,"Mismatch applied_settings at iteration %0d",i);
if(dut.sent_settings !== refdut.sent_settings)$fatal(1,"Mismatch sent_settings at iteration %0d",i);
if(dut.applied_context !== refdut.applied_context)$fatal(1,"Mismatch applied_context at iteration %0d",i);
if(dut.sent_context !== refdut.sent_context)$fatal(1,"Mismatch sent_context at iteration %0d",i);
if(dut.settings_updating !== refdut.settings_updating)$fatal(1,"Mismatch settings_updating at iteration %0d",i);
if(dut.ready_immediate !== refdut.ready_immediate)$fatal(1,"Mismatch ready_immediate at iteration %0d",i);
if(dut.ready_toggle !== refdut.ready_toggle)$fatal(1,"Mismatch ready_toggle at iteration %0d",i);
if(dut.ready_slot !== refdut.ready_slot)$fatal(1,"Mismatch ready_slot at iteration %0d",i);
if(dut.display_pending !== refdut.display_pending)$fatal(1,"Mismatch display_pending at iteration %0d",i);
if(dut.display_target !== refdut.display_target)$fatal(1,"Mismatch display_target at iteration %0d",i);
if(dut.current_source_width !== refdut.current_source_width)$fatal(1,"Mismatch current_source_width at iteration %0d",i);
if(dut.current_source_height !== refdut.current_source_height)$fatal(1,"Mismatch current_source_height at iteration %0d",i);
if(dut.award_notice !== refdut.award_notice)$fatal(1,"Mismatch award_notice at iteration %0d",i);
if(dut.last_transfer_error !== refdut.last_transfer_error)$fatal(1,"Mismatch last_transfer_error at iteration %0d",i);
if(dut.have_current !== refdut.have_current)$fatal(1,"Mismatch have_current at iteration %0d",i);
end endtask
initial begin
force dut.got=got;
force dut.tx_busy=tx_busy;
force dut.incoming=incoming;
force refdut.got=got;
force refdut.tx_busy=tx_busy;
force refdut.incoming=incoming;
repeat(3)@(negedge clk);rst=0;
for(i=0;i<20000;i=i+1)begin
 @(negedge clk);
 if(i%3==0)begin
  // Visit every one-hot state with arbitrary timer values, including
  // timeout boundaries and overflow; all other control state is retained.
  dut.state_flags=16'd1<<(i%16);refdut.state_flags=dut.state_flags;
  case(i%9)
   0:sample=0;1:sample=74999999;2:sample=75000000;
   3:sample=2999999999;4:sample=3000000000;
   5:sample=3375000000;6:sample=32'hffffffff;default:sample=$random;
  endcase
  refdut.timer=sample;dut.timer_count=sample;dut.timer_reset=0;
 end
 prev=$random;nxt=($random%7==0);mode=$random;award=($random%13==0);
 transition=$random;commit=$random;armed=$random;done=$random;fault=($random%9==0);
 if(i%19==0)settings=$random & 19'h3ffff;crc=$random;
 tx_busy=$random;got=$random;
 incoming={$random,$random,$random,$random,$random};
 // Exercise matching replies as well as rejected packets.
 if(i%2==0)begin incoming[151:120]=dut.session;incoming[119:104]=dut.request_seq;incoming[103:96]={5'd0,dut.target};end
 incoming[159:152]=i%20;incoming[42]=0;
 @(posedge clk);#1;compare;
 // Continue for two cycles to check the zero -> one encoding after a clear.
 repeat(2)begin @(posedge clk);#1;compare;end
end
$display("PASS timer encoding: 60000 cycle comparisons, 16 states, timeout boundaries and wraparound");$finish;
end
endmodule
