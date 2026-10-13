`timescale 1ns/1ps
module tb_playback_controls;
reg clk=0;always #5 clk=~clk;
reg rst=1,effect_valid=0,auto_valid=0,auto_value=0,reset_defaults=0;
reg [2:0] effect_value=0;
reg key_next=0,key_down=0,key_up=0,key_enter=0;
wire settings_mode,auto_enable;wire [3:0] setting_item;wire [2:0] effect_select;
saixian_settings_controller #(.CLK_FREQ_HZ(10),.TIMEOUT_SECONDS(100)) settings(
 .clk(clk),.rst(rst),.carousel_mode(1'b1),.key_next_item(key_next),
 .key_decrease(key_down),.key_enter_exit(key_enter),.key_increase(key_up),
 .hmi_setting_valid(1'b0),.hmi_setting_id(3'd0),.hmi_setting_value(8'd0),
 .hmi_reset_defaults(reset_defaults),.effect_valid(effect_valid),.effect_value(effect_value),
 .auto_valid(auto_valid),.auto_value(auto_value),.settings_mode(settings_mode),
 .setting_item(setting_item),.effect_select(effect_select),.auto_enable(auto_enable));
reg display_valid=1,transition_active=0,busy=0,enough_images=1,manual_event=0;
wire next_pulse;
integer auto_pulses=0;
integer i;
always @(posedge clk) if(next_pulse) auto_pulses=auto_pulses+1;
photo_auto_advance #(.CLK_FREQ_HZ(10),.HOLD_SECONDS(2)) autoplay(
 .clk(clk),.rst(rst),.enable(auto_enable),.display_valid(display_valid),
 .transition_active(transition_active),.busy(busy),.enough_images(enough_images),
 .settings_mode(settings_mode),.manual_event(manual_event),.next_pulse(next_pulse));
reg frame_tick=0,ready_toggle=0;
wire [2:0] transition_mode;wire [1:0] active_slot,new_slot;
wire commit,shown,active,slide_right;wire [10:0] slide_offset;wire [5:0] level;
saixian_transition transition(.clk(clk),.rst(rst),.frame_tick(frame_tick),
 .frame_ready_toggle(ready_toggle),.ready_buf_idx(2'd1),.ready_slide_right(1'b1),
 .effect_select(effect_select),.active_buf_idx(active_slot),.slide_new_buf_idx(new_slot),
 .frame_commit_toggle(commit),.display_valid(shown),.transition_active(active),
 .transition_mode(transition_mode),.slide_offset(slide_offset),.slide_right(slide_right),.transition_level(level));
task pulse_tick;
 begin @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;end
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 @(negedge clk);effect_value=6;effect_valid=1;auto_value=1;auto_valid=1;
 @(negedge clk);effect_valid=0;auto_valid=0;
 if(effect_select!=6) $fatal(1,"fixed transition setting ignored");
 // The settings controller accepts the two independent HMI commands in sequence.
 @(negedge clk);auto_value=1;auto_valid=1;
 @(negedge clk);auto_valid=0;
 if(!auto_enable) $fatal(1,"automatic mode ignored");
 repeat(10)@(negedge clk);
 manual_event=1;@(negedge clk);manual_event=0;
 repeat(18)@(negedge clk);
 if(auto_pulses!=0) $fatal(1,"timer did not restart after manual request");
 repeat(4)@(negedge clk);
 if(auto_pulses!=1) $fatal(1,"automatic next pulse missing");
 busy=1;repeat(25)@(negedge clk);
 if(auto_pulses!=1) $fatal(1,"automatic next repeated while busy");
 busy=0;
 key_enter=1;@(negedge clk);key_enter=0;
 for(i=0;i<8;i=i+1)begin key_next=1;@(negedge clk);key_next=0;@(negedge clk);end
 if(setting_item!=8) $fatal(1,"transition menu item missing");
 key_down=1;@(negedge clk);key_down=0;@(negedge clk);
 if(effect_select!=5) $fatal(1,"key did not change transition");
 key_up=1;@(negedge clk);key_up=0;@(negedge clk);
 key_next=1;@(negedge clk);key_next=0;@(negedge clk);
 if(setting_item!=9) $fatal(1,"auto menu item missing");
 key_down=1;@(negedge clk);key_down=0;@(negedge clk);
 if(auto_enable) $fatal(1,"key did not disable automatic mode");
 key_up=1;@(negedge clk);key_up=0;@(negedge clk);
 key_enter=1;@(negedge clk);key_enter=0;@(negedge clk);
 if(!auto_enable || settings_mode) $fatal(1,"key menu exit or auto enable failed");
 ready_toggle=1;repeat(3)@(negedge clk);pulse_tick();
 ready_toggle=0;repeat(3)@(negedge clk);pulse_tick();
 if(transition_mode!=5) $fatal(1,"fixed fade effect not selected");
 $display("PASS transition selection and automatic switching control");$finish;
end
initial begin #20000;$fatal(1,"timeout");end
endmodule
