module saixian_key_debounce #(
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire key_n,
    output reg  press_pulse
);

localparam integer COUNT_MAX = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg sync0;
reg sync1;
reg stable_n;
reg [19:0] count;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sync0      <= 1'b1;
        sync1      <= 1'b1;
        stable_n   <= 1'b1;
        count      <= 20'd0;
        press_pulse <= 1'b0;
    end else begin
        sync0       <= key_n;
        sync1       <= sync0;
        press_pulse <= 1'b0;

        if (sync1 == stable_n) begin
            count <= 20'd0;
        end else if (count == COUNT_MAX - 1) begin
            count    <= 20'd0;
            stable_n <= sync1;
            if (!sync1)
                press_pulse <= 1'b1;
        end else begin
            count <= count + 20'd1;
        end
    end
end

endmodule
