`timescale 1ns/1ps
module tb;
wire  actual_receive_fluid,reference_receive_fluid;
reg  settings_mode=0;
reg [18:0] settings_state=0;
wire  actual_settings_updating,reference_settings_updating;
wire  actual_high_color,reference_high_color;
wire  actual_format_changed,reference_format_changed;
reg  award_toggle=0;
wire  actual_award_available,reference_award_available;
wire  actual_award_scan_complete,reference_award_scan_complete;
wire  actual_award_loading,reference_award_loading;
wire [2:0] actual_award_notice,reference_award_notice;
wire [3:0] actual_last_transfer_error,reference_last_transfer_error;
wire [3:0] actual_first_transfer_origin,reference_first_transfer_origin;
wire [3:0] actual_first_transfer_error,reference_first_transfer_error;
reg  clk=0;
reg  rst=0;
reg  uart_rx=1;
wire  actual_uart_tx,reference_uart_tx;
reg  previous=0;
reg  next=0;
reg [1:0] active_slot=0;
reg [1:0] new_slot=0;
reg  transition_active=0;
reg  commit_toggle=0;
wire [1:0] actual_receive_slot,reference_receive_slot;
wire  actual_arm_toggle,reference_arm_toggle;
wire  actual_abort_toggle,reference_abort_toggle;
reg  rx_armed=0;
reg  rx_done=0;
reg  rx_fault=0;
reg [31:0] rx_crc=0;
wire  actual_ready_immediate,reference_ready_immediate;
wire  actual_ready_toggle,reference_ready_toggle;
wire [1:0] actual_ready_slot,reference_ready_slot;
wire  actual_ready_right,reference_ready_right;
wire [2:0] actual_image_count,reference_image_count;
wire [2:0] actual_current_image,reference_current_image;
wire  actual_busy,reference_busy;
wire [3:0] actual_error,reference_error;
wire [3:0] actual_debug_state,reference_debug_state;
wire [31:0] actual_debug_local_crc,reference_debug_local_crc;
wire [31:0] actual_debug_remote_crc,reference_debug_remote_crc;
wire  actual_cache_window_ready,reference_cache_window_ready;
wire [2:0] actual_cached_count,reference_cached_count;
wire [15:0] actual_current_source_width,reference_current_source_width;
wire [15:0] actual_current_source_height,reference_current_source_height;

reg got_driver=0,busy_driver=0;reg[159:0] packet_driver=0;
integer n,kind,selected,boundary,checks=0;reg[15:0] visited=0;
reg[31:0] random_state=32'hc4892a17;
function[31:0] random_word;input dummy;begin
 random_state=random_state^(random_state<<13);random_state=random_state^(random_state>>17);random_state=random_state^(random_state<<5);random_word=random_state;
end endfunction
always #5 clk=~clk;
photo_cached_control_a #(.TIMER_SCALE(750000),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.CHECK_FRAME_CRC(1),.FLUID(1)) dut(.receive_fluid(actual_receive_fluid),.settings_mode(settings_mode),.settings_state(settings_state),.settings_updating(actual_settings_updating),.high_color(actual_high_color),.format_changed(actual_format_changed),.award_toggle(award_toggle),.award_available(actual_award_available),.award_scan_complete(actual_award_scan_complete),.award_loading(actual_award_loading),.award_notice(actual_award_notice),.last_transfer_error(actual_last_transfer_error),.first_transfer_origin(actual_first_transfer_origin),.first_transfer_error(actual_first_transfer_error),.clk(clk),.rst(rst),.uart_rx(uart_rx),.uart_tx(actual_uart_tx),.previous(previous),.next(next),.active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(commit_toggle),.receive_slot(actual_receive_slot),.arm_toggle(actual_arm_toggle),.abort_toggle(actual_abort_toggle),.rx_armed(rx_armed),.rx_done(rx_done),.rx_fault(rx_fault),.rx_crc(rx_crc),.ready_immediate(actual_ready_immediate),.ready_toggle(actual_ready_toggle),.ready_slot(actual_ready_slot),.ready_right(actual_ready_right),.image_count(actual_image_count),.current_image(actual_current_image),.busy(actual_busy),.error(actual_error),.debug_state(actual_debug_state),.debug_local_crc(actual_debug_local_crc),.debug_remote_crc(actual_debug_remote_crc),.cache_window_ready(actual_cache_window_ready),.cached_count(actual_cached_count),.current_source_width(actual_current_source_width),.current_source_height(actual_current_source_height));
photo_cached_control_a_reference #(.TIMER_SCALE(750000),.SETTINGS_LINK(1),.AWARD_CONTROL(1),.CHECK_FRAME_CRC(1),.FLUID(1)) reference(.receive_fluid(reference_receive_fluid),.settings_mode(settings_mode),.settings_state(settings_state),.settings_updating(reference_settings_updating),.high_color(reference_high_color),.format_changed(reference_format_changed),.award_toggle(award_toggle),.award_available(reference_award_available),.award_scan_complete(reference_award_scan_complete),.award_loading(reference_award_loading),.award_notice(reference_award_notice),.last_transfer_error(reference_last_transfer_error),.first_transfer_origin(reference_first_transfer_origin),.first_transfer_error(reference_first_transfer_error),.clk(clk),.rst(rst),.uart_rx(uart_rx),.uart_tx(reference_uart_tx),.previous(previous),.next(next),.active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(commit_toggle),.receive_slot(reference_receive_slot),.arm_toggle(reference_arm_toggle),.abort_toggle(reference_abort_toggle),.rx_armed(rx_armed),.rx_done(rx_done),.rx_fault(rx_fault),.rx_crc(rx_crc),.ready_immediate(reference_ready_immediate),.ready_toggle(reference_ready_toggle),.ready_slot(reference_ready_slot),.ready_right(reference_ready_right),.image_count(reference_image_count),.current_image(reference_current_image),.busy(reference_busy),.error(reference_error),.debug_state(reference_debug_state),.debug_local_crc(reference_debug_local_crc),.debug_remote_crc(reference_debug_remote_crc),.cache_window_ready(reference_cache_window_ready),.cached_count(reference_cached_count),.current_source_width(reference_current_source_width),.current_source_height(reference_current_source_height));

always @(posedge clk)begin
 #1;
 if(actual_receive_fluid!==reference_receive_fluid || actual_settings_updating!==reference_settings_updating || actual_high_color!==reference_high_color || actual_format_changed!==reference_format_changed || actual_award_available!==reference_award_available || actual_award_scan_complete!==reference_award_scan_complete || actual_award_loading!==reference_award_loading || actual_award_notice!==reference_award_notice || actual_last_transfer_error!==reference_last_transfer_error || actual_first_transfer_origin!==reference_first_transfer_origin || actual_first_transfer_error!==reference_first_transfer_error || actual_uart_tx!==reference_uart_tx || actual_receive_slot!==reference_receive_slot || actual_arm_toggle!==reference_arm_toggle || actual_abort_toggle!==reference_abort_toggle || actual_ready_immediate!==reference_ready_immediate || actual_ready_toggle!==reference_ready_toggle || actual_ready_slot!==reference_ready_slot || actual_ready_right!==reference_ready_right || actual_image_count!==reference_image_count || actual_current_image!==reference_current_image || actual_busy!==reference_busy || actual_error!==reference_error || actual_debug_state!==reference_debug_state || actual_debug_local_crc!==reference_debug_local_crc || actual_debug_remote_crc!==reference_debug_remote_crc || actual_cache_window_ready!==reference_cache_window_ready || actual_cached_count!==reference_cached_count || actual_current_source_width!==reference_current_source_width || actual_current_source_height!==reference_current_source_height
    || dut.state!==reference.state || dut.timer!==reference.timer || dut.message!==reference.message || dut.send!==reference.send
    || dut.session!==reference.session || dut.request_seq!==reference.request_seq || dut.cache_valid!==reference.cache_valid)
  $fatal(1,"onehot controller mismatch check=%0d actual state=%0d ref=%0d",checks,dut.state,reference.state);
 if(!rst && (dut.state_flags==0 || (dut.state_flags&(dut.state_flags-1))!=0))$fatal(1,"state is not onehot");
 if(!rst)visited[dut.state]=1'b1;
 checks=checks+1;
end
initial begin
 force dut.got=got_driver;force reference.got=got_driver;
 force dut.incoming=packet_driver;force reference.incoming=packet_driver;
 force dut.tx_busy=busy_driver;force reference.tx_busy=busy_driver;
 rst=1;repeat(5)@(negedge clk);rst=0;
 for(n=0;n<60000;n=n+1)begin
  rst=n>0 && n%10007==0;
  settings_mode=random_word(0);settings_state=random_word(0);
  previous=(n%31==0);next=(n%37==0);award_toggle=n[7];
  active_slot=random_word(0)%3;new_slot=random_word(0)%3;
  transition_active=(n%11==0);commit_toggle=n[5];
  rx_armed=random_word(0);rx_done=(n%17==0);rx_fault=(n%53==0);rx_crc=random_word(0);
  busy_driver=random_word(0);got_driver=(n%7==0);
  case(n%11)0:kind=2;1:kind=3;2:kind=6;3:kind=9;4:kind=10;5:kind=11;6:kind=13;7:kind=15;8:kind=17;9:kind=18;default:kind=0;endcase
  packet_driver={kind[7:0],dut.session,dut.request_seq,{5'd0,dut.target},8'd2,dut.frame_bytes,rx_crc,8'hc6,16'd0};
  if(n%13==0)packet_driver[151:120]=random_word(0);
  if(n%19==0)packet_driver[119:104]=random_word(0);
  if(n%23==0)packet_driver[103:96]=random_word(0);
  if(n%83==0)begin
   selected=(n/83)%16;dut.state_flags=(16'd1<<selected);reference.state=selected;
   case((n/83)%7)0:boundary=0;1:boundary=99;2:boundary=199;3:boundary=499;4:boundary=3999;5:boundary=4499;default:boundary=-1;endcase
   dut.timer=boundary;reference.timer=boundary;
  end
  @(negedge clk);
 end
 rst=1;repeat(3)@(negedge clk);
 if(visited!=16'hffff)$fatal(1,"not all states covered: %h",visited);
 $display("PASS explicit onehot controller: %0d exact cycles, all 16 states, every timeout boundary and wrap, UART payloads, CRC/errors, settings/awards/cache navigation and reset",checks);$finish;
end
endmodule
