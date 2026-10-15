`timescale 1ns/1ps
module tb_audio_repair_settings;
reg clk=0;always #5 clk=~clk;
reg rst=1,n=0,d=0,e=0,u=0,defaults=0;wire mode,repair;wire [3:0] item;integer i;
photo_unified_settings_controller #(.CLK_FREQ_HZ(1000)) s(.clk(clk),.rst(rst),.carousel_mode(1'b1),
 .key_next_item(n),.key_decrease(d),.key_enter_exit(e),.key_increase(u),.hmi_setting_valid(1'b0),.hmi_setting_id(3'd0),.hmi_setting_value(8'd0),
 .hmi_reset_defaults(defaults),.effect_valid(1'b0),.effect_value(3'd0),.auto_valid(1'b0),.auto_value(1'b0),.audio_view_valid(1'b0),.audio_view_value(1'b0),
 .color_mode_valid(1'b0),.color_mode_value(1'b0),.settings_mode(mode),.setting_item(item),.audio_repair_enable(repair));
initial begin
 repeat(3)@(negedge clk);rst=0;if(repair!==0)$fatal(1,"repair default");
 e=1;@(negedge clk);e=0;
 for(i=0;i<12;i=i+1)begin n=1;@(negedge clk);n=0;@(negedge clk);end
 if(item!=12 || !mode)$fatal(1,"repair item unreachable");
 u=1;@(negedge clk);u=0;if(!repair)$fatal(1,"KEY4 enable");
 d=1;@(negedge clk);d=0;if(repair)$fatal(1,"KEY2 disable");
 u=1;@(negedge clk);u=0;n=1;@(negedge clk);n=0;if(item!=0 || !repair)$fatal(1,"wrap/persistence");
 defaults=1;@(negedge clk);defaults=0;if(repair)$fatal(1,"restore defaults");
 $display("PASS 13 settings items, repair default/off/on/reset and wrap");$finish;
end
endmodule
