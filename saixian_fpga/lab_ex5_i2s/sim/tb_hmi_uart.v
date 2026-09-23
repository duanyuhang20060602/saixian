`timescale 1ns/1ps

module tb_hmi_uart;
localparam integer CLKS_PER_BIT = 8;

reg clk = 1'b0;
reg rst = 1'b1;
reg uart_rx = 1'b1;
wire start_pulse, pause_pulse, finish_pulse, prev_pulse, next_pulse;
wire setting_valid, reset_defaults_pulse, frame_error_pulse;
wire [2:0] setting_id;
wire [7:0] setting_value;

integer start_count = 0;
integer setting_count = 0;
integer error_count = 0;

always #5 clk = ~clk;

saixian_hmi_uart #(.CLK_FREQ_HZ(800),.BAUD_RATE(100)) dut(
    .clk(clk),.rst(rst),.uart_rx(uart_rx),
    .start_pulse(start_pulse),.pause_pulse(pause_pulse),.finish_pulse(finish_pulse),
    .prev_pulse(prev_pulse),.next_pulse(next_pulse),
    .setting_valid(setting_valid),.setting_id(setting_id),.setting_value(setting_value),
    .reset_defaults_pulse(reset_defaults_pulse),.frame_error_pulse(frame_error_pulse)
);

always @(posedge clk) begin
    if (start_pulse) start_count = start_count + 1;
    if (setting_valid) setting_count = setting_count + 1;
    if (frame_error_pulse) error_count = error_count + 1;
end

task send_uart_byte;
    input [7:0] value;
    integer bit_index;
    begin
        uart_rx = 1'b0;
        repeat (CLKS_PER_BIT) @(posedge clk);
        for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
            uart_rx = value[bit_index];
            repeat (CLKS_PER_BIT) @(posedge clk);
        end
        uart_rx = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
    end
endtask

task send_frame;
    input [7:0] command;
    input [7:0] value;
    begin
        send_uart_byte(8'h55);
        send_uart_byte(command);
        send_uart_byte(value);
        send_uart_byte(8'h00);
        send_uart_byte(8'hff);
        send_uart_byte(8'hff);
        send_uart_byte(8'hff);
    end
endtask

initial begin
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (5) @(posedge clk);

    send_frame(8'h01, 8'd0);
    repeat (5) @(posedge clk);
    if (start_count != 1) begin
        $display("FAIL: start frame count=%0d", start_count);
        $finish;
    end

    send_frame(8'h13, 8'd75);
    repeat (5) @(posedge clk);
    if ((setting_count != 1) || (setting_id != 3'd3) || (setting_value != 8'd75)) begin
        $display("FAIL: setting count=%0d id=%0d value=%0d", setting_count, setting_id, setting_value);
        $finish;
    end

    // Corrupt the reserved byte. No command may be emitted.
    send_uart_byte(8'h55);
    send_uart_byte(8'h01);
    send_uart_byte(8'h00);
    send_uart_byte(8'h01);
    send_uart_byte(8'hff);
    send_uart_byte(8'hff);
    send_uart_byte(8'hff);
    repeat (5) @(posedge clk);
    if ((start_count != 1) || (error_count == 0)) begin
        $display("FAIL: corrupt frame was not rejected");
        $finish;
    end

    $display("PASS: TJC UART framing and command decode");
    $finish;
end
endmodule
