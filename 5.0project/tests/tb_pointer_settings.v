`timescale 1ns/1ps
module tb_pointer_settings;
reg clk=0;always #5 clk=~clk;
reg rst=1,enter=0,p=0,inc=0,kn=0,kp=0;reg [3:0] row=0;
wire mode,edge_on;wire [3:0] item,volume;wire [4:0] effect;integer i;
photo_unified_settings_controller #(.CLK_FREQ_HZ(1000),.POINTER_CONTROL(1)) dut(.clk(clk),.rst(rst),.carousel_mode(1'b1),
 .pointer_valid(p),.pointer_item(row),.pointer_increase(inc),.key_next_item(kn),.key_decrease(1'b0),.key_increase(kp),.key_enter_exit(enter),
 .hmi_setting_valid(1'b0),.hmi_reset_defaults(1'b0),.effect_valid(1'b0),.auto_valid(1'b0),
 .edge_valid(1'b0),.color_mode_valid(1'b0),.audio_view_valid(1'b0),.settings_mode(mode),
 .setting_item(item),.volume_setting(volume),.effect_select(effect),.edge_enable(edge_on));
task tap;input [3:0] r;input up;
begin row=r;inc=up;p=1;@(negedge clk);p=0;@(negedge clk);end endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 tap(0,1);if(volume!=5)$fatal(1,"closed menu no edit");
 enter=1;@(negedge clk);enter=0;@(negedge clk);
 if(!mode)$fatal(1,"open menu");
 tap(0,1);if(volume!=6 || item!=0)$fatal(1,"increase");
 tap(0,0);if(volume!=5)$fatal(1,"decrease");
 tap(13,1);if(!edge_on || item!=13)$fatal(1,"direct select last row");
 tap(13,0);if(edge_on)$fatal(1,"off");
 for(i=0;i<15;i=i+1)tap(8,1);
 if(effect!=11)$fatal(1,"effect cap");
 tap(15,1);if(item!=8 || effect!=11)$fatal(1,"invalid row");
 kn=1;@(negedge clk);kn=0;@(negedge clk);if(item!=9)$fatal(1,"physical keys");
 enter=1;@(negedge clk);enter=0;@(negedge clk);if(mode)$fatal(1,"close menu");
 $display("PASS pointer menu select/increase/decrease/toggle/limits/physical keys/open/close");$finish;
end
endmodule
