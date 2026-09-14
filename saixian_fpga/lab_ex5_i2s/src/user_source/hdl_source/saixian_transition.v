module saixian_transition(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       frame_ready_toggle,
    input  wire [1:0] ready_buf_idx,
    output reg  [1:0] active_buf_idx,
    output reg        frame_commit_toggle,
    output reg        display_valid,
    output reg        transition_active,
    output reg  [5:0] transition_level
);

reg ready_sync0;
reg ready_sync1;
reg ready_seen;
reg [1:0] ready_buf_sync0;
reg [1:0] ready_buf_sync1;
reg [1:0] pending_buf;
reg       uncover;
reg [1:0] full_cover_hold;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        ready_sync0         <= 1'b0;
        ready_sync1         <= 1'b0;
        ready_seen          <= 1'b0;
        ready_buf_sync0     <= 2'd0;
        ready_buf_sync1     <= 2'd0;
        pending_buf         <= 2'd0;
        active_buf_idx      <= 2'd0;
        frame_commit_toggle <= 1'b0;
        display_valid       <= 1'b0;
        transition_active   <= 1'b0;
        transition_level    <= 6'd0;
        uncover             <= 1'b0;
        full_cover_hold     <= 2'd0;
    end else begin
        ready_sync0     <= frame_ready_toggle;
        ready_sync1     <= ready_sync0;
        ready_buf_sync0 <= ready_buf_idx;
        ready_buf_sync1 <= ready_buf_sync0;

        if (frame_tick) begin
            if (!transition_active && (ready_sync1 != ready_seen)) begin
                ready_seen        <= ready_sync1;
                pending_buf       <= ready_buf_sync1;
                transition_active <= 1'b1;
                transition_level  <= 6'd0;
                uncover           <= 1'b0;
                full_cover_hold   <= 2'd0;
            end else if (transition_active && !uncover) begin
                if (transition_level >= 6'd30) begin
                    transition_level    <= 6'd32;
                    active_buf_idx      <= pending_buf;
                    frame_commit_toggle <= ~frame_commit_toggle;
                    display_valid       <= 1'b1;
                    uncover             <= 1'b1;
                    // The frame reader synchronizes active_buf_idx into the
                    // SDRAM clock domain and clears/refills its async FIFO.
                    // Keep the curtain fully closed for two more frames so no
                    // words from the previous framebuffer can be uncovered.
                    full_cover_hold     <= 2'd2;
                end else begin
                    transition_level <= transition_level + 6'd2;
                end
            end else if (transition_active) begin
                if (full_cover_hold != 0) begin
                    transition_level <= 6'd32;
                    full_cover_hold  <= full_cover_hold - 1'b1;
                end else if (transition_level <= 6'd2) begin
                    transition_level  <= 6'd0;
                    transition_active <= 1'b0;
                    uncover           <= 1'b0;
                end else begin
                    transition_level <= transition_level - 6'd2;
                end
            end
        end
    end
end

endmodule
