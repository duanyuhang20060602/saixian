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
    output reg touch_valid,output wire [9:0] touch_x,output wire [8:0] touch_y,
    output wire touch_down,output reg touch_mode_valid,touch_mode_value,
    output reg project_valid,output reg [1:0] project_value,
    output reg        start_pulse,
    output reg        pause_set_pulse, resume_pulse,
    output reg [2:0]  page_id,
    output reg        page_notify_pulse,
    output reg        pause_pulse,
    output reg        finish_pulse,
    output reg        prev_pulse,
    output reg        next_pulse,
    output reg        music_next_pulse,
    output reg        result_blue_pulse,
    output reg        result_red_pulse,
    output reg        result_sprint_pulse,
    output reg        result_stop_pulse,
    output reg        setting_valid,
    output reg [2:0]  setting_id,
    output reg [7:0]  setting_value,
    output reg        effect_valid,
    output reg [4:0]  effect_value,
    output reg        auto_valid,
    output reg        auto_value,
    output reg audio_view_valid,audio_view_value,
    output reg color_mode_valid,color_mode_value,
    output reg edge_valid,edge_value,
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

// UART input is asynchronous to the parameterized video clock.
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

reg [3:0] frame_index;
reg [9:0] touch_frame_x;reg [8:0] touch_frame_y;
reg touch_x_high_ok,touch_y_high_ok,touch_state_ok;
reg touch_frame_state;reg [7:0] touch_sum;
// Payload is meaningful only with touch_valid; reuse the pending frame storage.
assign touch_x=touch_frame_x;assign touch_y=touch_frame_y;assign touch_down=touch_frame_state;
reg touch_check_ok;
reg [7:0] frame_command;
reg [7:0] frame_value;
// Abandon incomplete messages after four character times of silence.
localparam integer FRAME_TIMEOUT = CLKS_PER_BIT * 40;
reg [31:0] frame_idle;

task decode_frame;
    begin
        case (frame_command)
            8'h01: if (frame_value == 0) start_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h02: if (frame_value == 0) pause_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h03: if (frame_value == 0) finish_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h04: if (frame_value == 0) prev_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h05: if (frame_value == 0) next_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h06: if (frame_value == 0) pause_set_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h08: if (frame_value == 0) music_next_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h07: if (frame_value == 0) resume_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h24: if(frame_value<=2)begin project_valid<=1;project_value<=frame_value[1:0];end else frame_error_pulse<=1;
            8'h31: if(frame_value<=1)begin touch_mode_valid<=1;touch_mode_value<=frame_value[0];end else frame_error_pulse<=1;
            8'h30: if (frame_value <= 4) begin page_id <= frame_value[2:0]; page_notify_pulse <= 1'b1; end else frame_error_pulse <= 1'b1;
            8'h10: begin setting_valid <= 1'b1; setting_id <= 3'd0; setting_value <= frame_value; end
            8'h11: begin setting_valid <= 1'b1; setting_id <= 3'd1; setting_value <= frame_value; end
            8'h12: begin setting_valid <= 1'b1; setting_id <= 3'd2; setting_value <= frame_value; end
            8'h13: begin setting_valid <= 1'b1; setting_id <= 3'd3; setting_value <= frame_value; end
            8'h14: begin setting_valid <= 1'b1; setting_id <= 3'd4; setting_value <= frame_value; end
            8'h15: begin
                if (frame_value <= 1) begin setting_valid <= 1'b1; setting_id <= 3'd5; setting_value <= frame_value; end
                else frame_error_pulse <= 1'b1;
            end
            8'h16: begin
                if (frame_value <= 1) begin setting_valid <= 1'b1; setting_id <= 3'd6; setting_value <= frame_value; end
                else frame_error_pulse <= 1'b1;
            end
            8'h1f: if (frame_value == 0) reset_defaults_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h17: begin
                if(frame_value<=2) begin setting_valid<=1'b1;setting_id<=3'd7;setting_value<=frame_value;end
                else frame_error_pulse<=1'b1;
            end
            8'h18: begin
                if (frame_value <= 11) begin effect_valid<=1'b1; effect_value<=frame_value[4:0]; end
                else frame_error_pulse<=1'b1;
            end
            8'h1c: if(frame_value<=1)begin edge_valid<=1;edge_value<=frame_value[0];end else frame_error_pulse<=1;
            8'h1b: if(frame_value<=1)begin color_mode_valid<=1;color_mode_value<=frame_value[0];end else frame_error_pulse<=1;
            8'h1a: if(frame_value<=1)begin audio_view_valid<=1;audio_view_value<=frame_value[0];end else frame_error_pulse<=1;
            8'h19: begin
                if (frame_value <= 1) begin auto_valid<=1'b1; auto_value<=frame_value[0]; end
                else frame_error_pulse<=1'b1;
            end
            8'h20: begin
                if (frame_value == 0) result_blue_pulse <= 1'b1;
                else frame_error_pulse <= 1'b1;
            end
            8'h21: begin
                if (frame_value == 0) result_red_pulse <= 1'b1;
                else frame_error_pulse <= 1'b1;
            end
            8'h23: if (frame_value == 0) result_stop_pulse <= 1'b1; else frame_error_pulse <= 1'b1;
            8'h22: begin
                if (frame_value == 0) result_sprint_pulse <= 1'b1;
                else frame_error_pulse <= 1'b1;
            end
            default: frame_error_pulse  <= 1'b1;
        endcase
    end
endtask

always @(posedge clk or posedge rst) begin
    if (rst) begin
        touch_valid<=0;touch_x_high_ok<=0;touch_y_high_ok<=0;touch_state_ok<=0;
        touch_mode_valid<=0;touch_mode_value<=0;touch_frame_x<=0;touch_frame_y<=0;
        touch_frame_state<=0;touch_sum<=0;touch_check_ok<=0;
        project_value<=0;frame_index          <= 3'd0;
        page_id <= 3'd0;
        frame_idle           <= 0;
        frame_command        <= 8'd0;
        frame_value          <= 8'd0;
        project_valid<=0;start_pulse          <= 1'b0;
        pause_set_pulse <= 1'b0; resume_pulse <= 1'b0; page_notify_pulse <= 1'b0;
        pause_pulse          <= 1'b0;
        finish_pulse         <= 1'b0;
        prev_pulse           <= 1'b0;
        next_pulse           <= 1'b0;
        music_next_pulse     <= 1'b0;
        result_blue_pulse    <= 1'b0;
        result_red_pulse     <= 1'b0;
        result_sprint_pulse  <= 1'b0;
        result_stop_pulse    <= 1'b0;
        setting_valid        <= 1'b0;
        setting_id           <= 3'd0;
        setting_value        <= 8'd0;
        effect_valid         <= 1'b0;
        effect_value         <= 3'd0;
        auto_valid           <= 1'b0;audio_view_valid<=0;color_mode_valid<=0;edge_valid<=0;
        auto_value           <= 1'b0;audio_view_value<=0;color_mode_value<=0;edge_value<=0;
        reset_defaults_pulse <= 1'b0;
        frame_error_pulse    <= 1'b0;
    end else begin
        touch_valid<=0;touch_mode_valid<=0;
        project_valid<=0;start_pulse          <= 1'b0;
        pause_set_pulse <= 1'b0; resume_pulse <= 1'b0; page_notify_pulse <= 1'b0;
        pause_pulse          <= 1'b0;
        finish_pulse         <= 1'b0;
        prev_pulse           <= 1'b0;
        next_pulse           <= 1'b0;
        music_next_pulse     <= 1'b0;
        result_blue_pulse    <= 1'b0;
        result_red_pulse     <= 1'b0;
        result_sprint_pulse  <= 1'b0;
        result_stop_pulse    <= 1'b0;
        setting_valid        <= 1'b0;
        effect_valid         <= 1'b0;
        auto_valid           <= 1'b0;audio_view_valid<=0;color_mode_valid<=0;edge_valid<=0;
        reset_defaults_pulse <= 1'b0;
        frame_error_pulse    <= 1'b0;

        if (frame_index == 0 || rx_byte_valid)
            frame_idle <= 0;
        else if (frame_idle >= FRAME_TIMEOUT-1) begin
            frame_idle <= 0;
            frame_index <= 0;
            frame_error_pulse <= 1'b1;
        end else frame_idle <= frame_idle + 1'b1;

        if (rx_byte_valid) begin
            case (frame_index)
                3'd0: begin
                    if (rx_byte == 8'h55) frame_index <= 4'd1;
                    else if(rx_byte==8'ha6)begin frame_index<=4'd7;touch_sum<=8'ha6;end
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
                4'd7:begin touch_frame_x[7:0]<=rx_byte;touch_sum<=touch_sum+rx_byte;frame_index<=8;end
                4'd8:begin touch_frame_x[9:8]<=rx_byte[1:0];touch_x_high_ok<=rx_byte[7:2]==0;touch_sum<=touch_sum+rx_byte;frame_index<=9;end
                4'd9:begin touch_frame_y[7:0]<=rx_byte;touch_sum<=touch_sum+rx_byte;frame_index<=10;end
                4'd10:begin touch_frame_y[8]<=rx_byte[0];touch_y_high_ok<=rx_byte[7:1]==0;touch_sum<=touch_sum+rx_byte;frame_index<=11;end
                4'd11:begin touch_frame_state<=rx_byte[0];touch_state_ok<=rx_byte<=1;touch_sum<=touch_sum+rx_byte;frame_index<=12;end
                4'd12:begin
                    touch_check_ok<=rx_byte==touch_sum && touch_frame_x<800 && touch_frame_y<480 && touch_state_ok && touch_x_high_ok && touch_y_high_ok;
                    frame_index<=13;
                end
                4'd13,4'd14:begin
                    if(rx_byte==8'hff)frame_index<=frame_index+1'b1;
                    else begin frame_index<=0;frame_error_pulse<=1;end
                end
                4'd15:begin
                    frame_index<=0;
                    if(rx_byte==8'hff && touch_check_ok)begin
                        touch_valid<=1;
                    end else frame_error_pulse<=1;
                end
                default: frame_index <= 3'd0;
            endcase
        end
    end
end

endmodule
