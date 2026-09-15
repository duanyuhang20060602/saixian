// TJC X5 serial-screen receiver.
// Wire protocol (115200 8N1): 55 CMD VALUE 00 FF FF FF
// The fixed trailer gives the parser a simple integrity check and lets it
// recover from a byte slip without resetting the FPGA.
module saixian_hmi_uart #(
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer BAUD_RATE   = 115_200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       uart_rx,
    output reg        start_pulse,
    output reg        pause_pulse,
    output reg        finish_pulse,
    output reg        prev_pulse,
    output reg        next_pulse,
    output reg        setting_valid,
    output reg [2:0]  setting_id,
    output reg [7:0]  setting_value,
    output reg        reset_defaults_pulse,
    output reg        frame_error_pulse
);

localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
localparam integer HALF_BIT     = CLKS_PER_BIT / 2;

localparam [1:0] RX_IDLE  = 2'd0;
localparam [1:0] RX_START = 2'd1;
localparam [1:0] RX_DATA  = 2'd2;
localparam [1:0] RX_STOP  = 2'd3;

reg [1:0]  rx_state;
reg [15:0] rx_clock_count;
reg [2:0]  rx_bit_index;
reg [7:0]  rx_shift;
reg        rx_byte_valid;
reg [7:0]  rx_byte;
reg [1:0]  rx_sync;

// UART input is asynchronous to the 25 MHz video clock.
always @(posedge clk or posedge rst) begin
    if (rst)
        rx_sync <= 2'b11;
    else
        rx_sync <= {rx_sync[0], uart_rx};
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rx_state       <= RX_IDLE;
        rx_clock_count <= 16'd0;
        rx_bit_index   <= 3'd0;
        rx_shift       <= 8'd0;
        rx_byte_valid  <= 1'b0;
        rx_byte        <= 8'd0;
    end else begin
        rx_byte_valid <= 1'b0;
        case (rx_state)
            RX_IDLE: begin
                rx_clock_count <= 16'd0;
                rx_bit_index   <= 3'd0;
                if (!rx_sync[1])
                    rx_state <= RX_START;
            end
            RX_START: begin
                if (rx_clock_count == HALF_BIT - 1) begin
                    rx_clock_count <= 16'd0;
                    if (!rx_sync[1])
                        rx_state <= RX_DATA;
                    else
                        rx_state <= RX_IDLE;
                end else
                    rx_clock_count <= rx_clock_count + 1'b1;
            end
            RX_DATA: begin
                if (rx_clock_count == CLKS_PER_BIT - 1) begin
                    rx_clock_count       <= 16'd0;
                    rx_shift[rx_bit_index] <= rx_sync[1];
                    if (rx_bit_index == 3'd7) begin
                        rx_bit_index <= 3'd0;
                        rx_state     <= RX_STOP;
                    end else
                        rx_bit_index <= rx_bit_index + 1'b1;
                end else
                    rx_clock_count <= rx_clock_count + 1'b1;
            end
            RX_STOP: begin
                if (rx_clock_count == CLKS_PER_BIT - 1) begin
                    rx_clock_count <= 16'd0;
                    rx_state       <= RX_IDLE;
                    if (rx_sync[1]) begin
                        rx_byte       <= rx_shift;
                        rx_byte_valid <= 1'b1;
                    end
                end else
                    rx_clock_count <= rx_clock_count + 1'b1;
            end
            default: rx_state <= RX_IDLE;
        endcase
    end
end

reg [2:0] frame_index;
reg [7:0] frame_command;
reg [7:0] frame_value;

task decode_frame;
    begin
        case (frame_command)
            8'h01: start_pulse          <= 1'b1;
            8'h02: pause_pulse          <= 1'b1;
            8'h03: finish_pulse         <= 1'b1;
            8'h04: prev_pulse           <= 1'b1;
            8'h05: next_pulse           <= 1'b1;
            8'h10: begin setting_valid <= 1'b1; setting_id <= 3'd0; setting_value <= frame_value; end
            8'h11: begin setting_valid <= 1'b1; setting_id <= 3'd1; setting_value <= frame_value; end
            8'h12: begin setting_valid <= 1'b1; setting_id <= 3'd2; setting_value <= frame_value; end
            8'h13: begin setting_valid <= 1'b1; setting_id <= 3'd3; setting_value <= frame_value; end
            8'h14: begin setting_valid <= 1'b1; setting_id <= 3'd4; setting_value <= frame_value; end
            8'h1f: reset_defaults_pulse <= 1'b1;
            default: frame_error_pulse  <= 1'b1;
        endcase
    end
endtask

always @(posedge clk or posedge rst) begin
    if (rst) begin
        frame_index          <= 3'd0;
        frame_command        <= 8'd0;
        frame_value          <= 8'd0;
        start_pulse          <= 1'b0;
        pause_pulse          <= 1'b0;
        finish_pulse         <= 1'b0;
        prev_pulse           <= 1'b0;
        next_pulse           <= 1'b0;
        setting_valid        <= 1'b0;
        setting_id           <= 3'd0;
        setting_value        <= 8'd0;
        reset_defaults_pulse <= 1'b0;
        frame_error_pulse    <= 1'b0;
    end else begin
        start_pulse          <= 1'b0;
        pause_pulse          <= 1'b0;
        finish_pulse         <= 1'b0;
        prev_pulse           <= 1'b0;
        next_pulse           <= 1'b0;
        setting_valid        <= 1'b0;
        reset_defaults_pulse <= 1'b0;
        frame_error_pulse    <= 1'b0;

        if (rx_byte_valid) begin
            case (frame_index)
                3'd0: begin
                    if (rx_byte == 8'h55)
                        frame_index <= 3'd1;
                end
                3'd1: begin frame_command <= rx_byte; frame_index <= 3'd2; end
                3'd2: begin frame_value   <= rx_byte; frame_index <= 3'd3; end
                3'd3: begin
                    if (rx_byte == 8'h00)
                        frame_index <= 3'd4;
                    else begin
                        frame_index       <= (rx_byte == 8'h55) ? 3'd1 : 3'd0;
                        frame_error_pulse <= 1'b1;
                    end
                end
                3'd4, 3'd5: begin
                    if (rx_byte == 8'hff)
                        frame_index <= frame_index + 1'b1;
                    else begin
                        frame_index       <= (rx_byte == 8'h55) ? 3'd1 : 3'd0;
                        frame_error_pulse <= 1'b1;
                    end
                end
                3'd6: begin
                    frame_index <= 3'd0;
                    if (rx_byte == 8'hff)
                        decode_frame();
                    else begin
                        frame_index       <= (rx_byte == 8'h55) ? 3'd1 : 3'd0;
                        frame_error_pulse <= 1'b1;
                    end
                end
                default: frame_index <= 3'd0;
            endcase
        end
    end
end

endmodule
