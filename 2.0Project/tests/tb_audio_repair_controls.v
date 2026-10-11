`timescale 1ns/1ps
module tb_audio_repair_controls;
reg clk=0,rst=1,kn=0,kd=0,ki=0,ke=0,defaults=0,carousel=1;
wire repair,settings;
wire [3:0] item,volume,brightness;
integer i;
always #5 clk=~clk;
saixian_settings_controller #(.CLK_FREQ_HZ(100),.TIMEOUT_SECONDS(1)) dut(
    .clk(clk),.rst(rst),.carousel_mode(carousel),.key_next_item(kn),.key_decrease(kd),
    .key_increase(ki),.key_enter_exit(ke),.hmi_setting_valid(1'b0),.hmi_setting_id(3'd0),
    .hmi_setting_value(8'd0),.hmi_reset_defaults(defaults),
    .audio_repair_setting(repair),.settings_mode(settings),.setting_item(item),
    .volume_setting(volume),.brightness_setting(brightness));
task enter_exit;begin @(negedge clk);ke=1;@(negedge clk);ke=0;end endtask
task next_item;begin @(negedge clk);kn=1;@(negedge clk);kn=0;end endtask
task increase;begin @(negedge clk);ki=1;@(negedge clk);ki=0;end endtask
task decrease;begin @(negedge clk);kd=1;@(negedge clk);kd=0;end endtask
initial begin
    repeat(3) @(negedge clk);rst=0;
    if(repair!==0 || settings!==0) $fatal(1,"default must be off");
    enter_exit();if(!settings || item!=0) $fatal(1,"KEY3 open settings");
    for(i=0;i<8;i=i+1) begin
        if(item!==4'(i)) $fatal(1,"old menu order changed at %d",i);
        next_item();
    end
    if(item!==8) $fatal(1,"ninth menu item unreachable");
    increase();if(!repair || volume!=5 || brightness!=4) $fatal(1,"KEY4 enable altered other settings");
    increase();if(!repair) $fatal(1,"repeated enable toggled off");
    decrease();if(repair) $fatal(1,"KEY2 disable");
    decrease();if(repair) $fatal(1,"repeated disable toggled on");
    increase();enter_exit();if(settings || !repair) $fatal(1,"KEY3 exit lost setting");
    enter_exit();if(!repair || item!=0) $fatal(1,"reentry lost setting");
    repeat(8) next_item();next_item();if(item!=0) $fatal(1,"nine-item wrap");
    repeat(110) @(negedge clk);if(settings || !repair) $fatal(1,"timeout lost repair state");
    enter_exit();carousel=0;@(negedge clk);
    if(settings || !repair) $fatal(1,"event exit lost repair state");
    carousel=1;defaults=1;@(negedge clk);defaults=0;
    if(repair || volume!=5 || brightness!=4) $fatal(1,"restore defaults");
    $display("PASS board repair controls: KEY3 enter/exit, 9-item order/wrap, KEY4 on, KEY2 off, retention, timeout and defaults");$finish;
end
endmodule
