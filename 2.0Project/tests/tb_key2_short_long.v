`timescale 1ns/1ps
module tb_key2_short_long;
reg clk=0, rst=1, key_n=1, press_pulse=0;
wire short_pulse, long_pulse;
reg result_mode=1, battle_busy=0;
wire continue_pulse, blue_select, red_select;
integer short_count=0, long_count=0;
integer continue_count=0, blue_count=0, red_count=0;
always #5 clk=~clk;

saixian_key_short_long #(.CLK_FREQ_HZ(1000),.HOLD_MS(100)) dut(
    .clk(clk),.rst(rst),.key_n(key_n),.press_pulse(press_pulse),
    .short_pulse(short_pulse),.long_pulse(long_pulse)
);
saixian_key2_result_router router(
    .result_mode(result_mode),.battle_busy(battle_busy),
    .short_pulse(short_pulse),.long_pulse(long_pulse),
    .continue_pulse(continue_pulse),.blue_select(blue_select),.red_select(red_select)
);

always @(posedge clk) begin
    if(short_pulse) short_count=short_count+1;
    if(long_pulse) long_count=long_count+1;
    if(continue_pulse) continue_count=continue_count+1;
    if(blue_select) blue_count=blue_count+1;
    if(red_select) red_count=red_count+1;
end

task arm_press;
begin
    key_n=0;
    repeat(4) @(negedge clk);
    press_pulse=1;
    @(negedge clk);
    press_pulse=0;
end
endtask

initial begin
    repeat(3) @(negedge clk); rst=0;

    arm_press;
    repeat(20) @(negedge clk);
    if(short_count!=0 || long_count!=0) $fatal(1,"short press fired before release");
    key_n=1;
    repeat(5) @(negedge clk);
    if(short_count!=1 || long_count!=0 || blue_count!=1 || red_count!=0)
        $fatal(1,"idle short press did not select blue exactly once");

    arm_press;
    repeat(110) @(negedge clk);
    if(short_count!=1 || long_count!=1 || blue_count!=1 || red_count!=1)
        $fatal(1,"idle one-second hold did not select red exactly once");
    repeat(20) @(negedge clk);
    if(long_count!=1) $fatal(1,"long press repeated while held");
    key_n=1;
    repeat(5) @(negedge clk);
    if(short_count!=1 || long_count!=1) $fatal(1,"long release emitted a short press");

    battle_busy=1;
    arm_press;
    repeat(20) @(negedge clk);
    key_n=1;
    repeat(5) @(negedge clk);
    if(continue_count!=1 || blue_count!=1 || red_count!=1)
        $fatal(1,"active-result short press restarted a winner instead of continuing");

    $display("PASS K2 idle short/long selects blue/red; active-result short press continues without restart");
    $finish;
end
endmodule
