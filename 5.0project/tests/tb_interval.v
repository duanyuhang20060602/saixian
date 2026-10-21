`timescale 1ns/1ps
module tb_interval;
reg clk=0;always #5 clk=~clk;
reg rst=1,enter=0,pointer=0,inc=0,next_item=0,reset_defaults=0;
reg [3:0] row=14;
wire [4:0] seconds;wire mode;wire [3:0] item;
photo_unified_settings_controller #(.CLK_FREQ_HZ(10),.TIMEOUT_SECONDS(100),.POINTER_CONTROL(1),.INTERVAL_CONTROL(1)) settings(
 .clk(clk),.rst(rst),.carousel_mode(1'b1),.pointer_valid(pointer),.pointer_item(row),.pointer_increase(inc),
 .key_next_item(next_item),.key_decrease(1'b0),.key_increase(1'b0),.key_enter_exit(enter),
 .hmi_setting_valid(1'b0),.hmi_reset_defaults(reset_defaults),.effect_valid(1'b0),.edge_valid(1'b0),.auto_valid(1'b0),.color_mode_valid(1'b0),.audio_view_valid(1'b0),
 .settings_mode(mode),.setting_item(item),.auto_interval_seconds(seconds));
reg enable=1,manual=0,transition=0,busy=0,menu=0,valid=1,enough=1;
reg [4:0] interval=1;wire pulse;
photo_auto_advance #(.CLK_FREQ_HZ(10),.ADJUSTABLE(1)) dut(.clk(clk),.rst(rst),.enable(enable),.display_valid(valid),.transition_active(transition),.busy(busy),.enough_images(enough),.settings_mode(menu),.manual_event(manual),.interval_seconds(interval),.next_pulse(pulse));
task tap;input up;begin @(negedge clk);pointer=1;inc=up;@(negedge clk);pointer=0;end endtask
task clocks;input integer n;integer j;begin for(j=0;j<n;j=j+1)begin @(posedge clk);#1;if(pulse)$fatal(1,"early auto pulse");end end endtask
integer i;
initial begin
 repeat(3)@(negedge clk);rst=0;enable=0;
 @(negedge clk);enter=1;@(negedge clk);enter=0;
 if(seconds!=5 || !mode)$fatal(1,"defaults/menu");
 for(i=0;i<40;i=i+1)tap(0);
 if(seconds!=1 || item!=14)$fatal(1,"minimum interval");
 for(i=0;i<40;i=i+1)tap(1);
 if(seconds!=30)$fatal(1,"maximum interval");
 @(negedge clk);next_item=1;@(negedge clk);next_item=0;if(item!=0)$fatal(1,"menu wrap");
 reset_defaults=1;@(negedge clk);reset_defaults=0;if(seconds!=5)$fatal(1,"restore interval");
 for(i=1;i<=30;i=i+1)begin
  @(negedge clk);interval=i;manual=1;enable=1;
  @(negedge clk);manual=0;clocks(i*10-1);
  @(posedge clk);#1;if(!pulse)$fatal(1,"missing auto pulse at %0ds",i);
 end
 @(negedge clk);interval=2;manual=1;@(negedge clk);manual=0;clocks(8);
 @(negedge clk);interval=1;@(posedge clk);#1;if(pulse)$fatal(1,"change resets timer");clocks(9);
 @(posedge clk);#1;if(!pulse)$fatal(1,"new interval");
 @(negedge clk);busy=1;clocks(40);busy=0;menu=1;clocks(40);menu=0;transition=1;clocks(40);
 $display("PASS adjustable auto advance: all 1..30s exact periods, edits reset, 1/30 bounds, defaults, menu wrap, busy/settings/transition hold");$finish;
end
endmodule
