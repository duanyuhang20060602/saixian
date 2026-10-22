`timescale 1ns/1ps
module tb;
reg clk=0,rst=1,next=0,enter=0,inc=0,dec=0,pointer=0;always #5 clk=~clk;
reg [3:0] row=0;wire [3:0] selected;wire repair,edge_on,mode;wire [4:0] interval;
photo_unified_settings_controller #(.CLK_FREQ_HZ(100000),.POINTER_CONTROL(1),.INTERVAL_CONTROL(1),.IMAGE_MENU(1)) dut(
 .clk(clk),.rst(rst),.carousel_mode(1'b1),.pointer_valid(pointer),.pointer_item(row),.pointer_increase(inc),
 .key_next_item(next),.key_decrease(dec),.key_enter_exit(enter),.key_increase(inc),
 .hmi_setting_valid(1'b0),.hmi_setting_id(3'd0),.hmi_setting_value(8'd0),.hmi_reset_defaults(1'b0),
 .effect_valid(1'b0),.effect_value(5'd0),.auto_valid(1'b0),.auto_value(1'b0),.audio_view_valid(1'b0),.audio_view_value(1'b0),
 .edge_valid(1'b0),.edge_value(1'b0),.edge_enable(edge_on),.audio_repair_enable(repair),.settings_mode(mode),.setting_item(selected),.auto_interval_seconds(interval));
task pulse_next;begin @(negedge clk);next=1;@(negedge clk);next=0;end endtask
task change;input [3:0] target;input up;
 begin @(negedge clk);row=target;pointer=1;inc=up;@(negedge clk);pointer=0;inc=0;end
endtask
integer n;
initial begin
 repeat(3)@(negedge clk);rst=0;enter=1;@(negedge clk);enter=0;
 if(!mode || selected!=1)$fatal(1,"image menu entry");
 for(n=2;n<=13;n=n+1)begin pulse_next;if(selected!=n)$fatal(1,"menu row order");end
 pulse_next;if(selected!=1)$fatal(1,"menu must wrap after interval");
 change(11,1);if(!repair || selected!=11)$fatal(1,"repair row moved incorrectly");
 change(12,1);if(!edge_on || selected!=12)$fatal(1,"edge row moved incorrectly");
 change(11,0);if(repair)$fatal(1,"repair decrease");change(12,0);if(edge_on)$fatal(1,"edge decrease");
 for(n=0;n<40;n=n+1)change(13,1);if(interval!=30)$fatal(1,"interval upper clamp");
 for(n=0;n<40;n=n+1)change(13,0);if(interval!=1)$fatal(1,"interval lower clamp");
 // Removed row 14 must not be selectable, including at the pointer boundary.
 change(14,0);if(selected!=13 || interval!=1)$fatal(1,"retired row accepted");
 $display("PASS RGB565-only menu: rows 1..13, keyboard wrap, repair/edge remapping, interval 1..30 clamp and retired-row rejection");$finish;
end
endmodule
