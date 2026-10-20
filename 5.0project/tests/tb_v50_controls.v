`timescale 1ns/1ps
module tb_v50_controls;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=1,next=0,up=0,down=0,enter=0;
wire effect_valid;wire[4:0] effect_value,effect;wire mode;wire[3:0] item;
integer i,received=0;reg[4:0] expected=0;
saixian_hmi_uart #(.CLK_FREQ_HZ(1152000)) hmi(.clk(clk),.rst(rst),.uart_rx(rx),
 .effect_valid(effect_valid),.effect_value(effect_value));
photo_unified_settings_controller #(.CLK_FREQ_HZ(1152000)) settings(.clk(clk),.rst(rst),.carousel_mode(1'b1),
 .key_next_item(next),.key_decrease(down),.key_enter_exit(enter),.key_increase(up),
 .hmi_setting_valid(1'b0),.hmi_setting_id(3'd0),.hmi_setting_value(8'd0),.hmi_reset_defaults(1'b0),
 .effect_valid(effect_valid),.effect_value(effect_value),.auto_valid(1'b0),.auto_value(1'b0),
 .audio_view_valid(1'b0),.audio_view_value(1'b0),.color_mode_valid(1'b0),.color_mode_value(1'b0),
 .edge_valid(1'b0),.edge_value(1'b0),.settings_mode(mode),.setting_item(item),.effect_select(effect));
always @(posedge clk)if(effect_valid)begin
 if(effect_value!==expected)$fatal(1,"HMI lost five-bit effect selection");received=received+1;
end
task byte_tx;input[7:0] b;integer k;begin
 @(negedge clk);rx=0;repeat(10)@(negedge clk);
 for(k=0;k<8;k=k+1)begin rx=b[k];repeat(10)@(negedge clk);end
 rx=1;repeat(10)@(negedge clk);
end endtask
task select_effect;input[7:0] e;begin
 byte_tx(8'h55);byte_tx(8'h18);byte_tx(e);byte_tx(0);byte_tx(255);byte_tx(255);byte_tx(255);repeat(20)@(negedge clk);
end endtask
initial begin
 repeat(5)@(negedge clk);rst=0;
 for(i=0;i<=11;i=i+1)begin expected=i;select_effect(i);if(effect!=i)$fatal(1,"fixed selection %0d",i);end
 select_effect(12);select_effect(255);if(effect!=11||received!=12)$fatal(1,"invalid selection accepted");
 enter=1;@(negedge clk);enter=0;
 for(i=0;i<8;i=i+1)begin next=1;@(negedge clk);next=0;@(negedge clk);end
 if(!mode||item!=8)$fatal(1,"effect menu item unreachable");
 up=1;@(negedge clk);up=0;if(effect!=11)$fatal(1,"effect menu maximum");
 for(i=0;i<12;i=i+1)begin down=1;@(negedge clk);down=0;@(negedge clk);end
 if(effect!=0)$fatal(1,"effect menu minimum");
 for(i=0;i<12;i=i+1)begin up=1;@(negedge clk);up=0;@(negedge clk);end
 if(effect!=11)$fatal(1,"eleventh effect unreachable from keys");
 $display("PASS HMI selections 0..11, rejected invalid values, all eleven effects reachable from on-board menu");$finish;
end
initial begin #2000000;$fatal(1,"controls timeout");end
endmodule
