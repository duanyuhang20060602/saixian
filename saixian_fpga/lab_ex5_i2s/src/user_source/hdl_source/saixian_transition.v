module saixian_transition(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_tick,
    input  wire       frame_ready_toggle,
    input  wire [1:0] ready_buf_idx,
    input  wire       ready_slide_right,
    output reg  [1:0] active_buf_idx,
    output reg  [1:0] slide_new_buf_idx,
    output reg        frame_commit_toggle,
    output reg        display_valid,
    output reg        transition_active,
    output reg  [9:0] slide_offset,
    output reg        slide_right,
    output reg  [5:0] transition_level
);

reg       ready_sync0;
reg       ready_sync1;
reg       ready_seen;
reg [1:0] ready_buf_sync0;
reg [1:0] ready_buf_sync1;
reg       ready_right_sync0;
reg       ready_right_sync1;
reg [4:0] slide_step;
reg       end_hold;

function [9:0] ease_offset;
    input [4:0] step;
    begin
        case (step)
            5'd0:  ease_offset = 10'd0;
            5'd1:  ease_offset = 10'd7;
            5'd2:  ease_offset = 10'd27;
            5'd3:  ease_offset = 10'd59;
            5'd4:  ease_offset = 10'd100;
            5'd5:  ease_offset = 10'd150;
            5'd6:  ease_offset = 10'd207;
            5'd7:  ease_offset = 10'd267;
            5'd8:  ease_offset = 10'd320;
            5'd9:  ease_offset = 10'd373;
            5'd10: ease_offset = 10'd433;
            5'd11: ease_offset = 10'd490;
            5'd12: ease_offset = 10'd540;
            5'd13: ease_offset = 10'd581;
            5'd14: ease_offset = 10'd613;
            5'd15: ease_offset = 10'd633;
            default: ease_offset = 10'd640;
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        ready_sync0         <= 1'b0;
        ready_sync1         <= 1'b0;
        ready_seen          <= 1'b0;
        ready_buf_sync0     <= 2'd0;
        ready_buf_sync1     <= 2'd0;
        ready_right_sync0   <= 1'b0;
        ready_right_sync1   <= 1'b0;
        active_buf_idx      <= 2'd0;
        slide_new_buf_idx   <= 2'd0;
        frame_commit_toggle <= 1'b0;
        display_valid       <= 1'b0;
        transition_active   <= 1'b0;
        slide_offset        <= 10'd0;
        slide_right         <= 1'b0;
        slide_step          <= 5'd0;
        end_hold            <= 1'b0;
        transition_level    <= 6'd0;
    end else begin
        ready_sync0       <= frame_ready_toggle;
        ready_sync1       <= ready_sync0;
        ready_buf_sync0   <= ready_buf_idx;
        ready_buf_sync1   <= ready_buf_sync0;
        ready_right_sync0 <= ready_slide_right;
        ready_right_sync1 <= ready_right_sync0;

        // The old curtain interface is retained for the OSD, but a true push
        // transition does not cover the image with a solid color.
        transition_level <= 6'd0;

        if (frame_tick) begin
            if (!transition_active && (ready_sync1 != ready_seen)) begin
                ready_seen        <= ready_sync1;
                slide_new_buf_idx <= ready_buf_sync1;

                // The first decoded image has no valid predecessor. Commit it
                // immediately; later images use the 16-frame eased slide.
                if (!display_valid) begin
                    active_buf_idx      <= ready_buf_sync1;
                    frame_commit_toggle <= ~frame_commit_toggle;
                    display_valid       <= 1'b1;
                    slide_offset        <= 10'd0;
                end else begin
                    transition_active <= 1'b1;
                    slide_right       <= ready_right_sync1;
                    slide_step        <= 5'd0;
                    slide_offset      <= 10'd0;
                    end_hold          <= 1'b0;
                end
            end else if (transition_active) begin
                if (end_hold) begin
                    // One complete frame at offset 640 guarantees that the
                    // memory-domain reader has shown only the new buffer before
                    // ownership is returned to the SD loader.
                    active_buf_idx      <= slide_new_buf_idx;
                    frame_commit_toggle <= ~frame_commit_toggle;
                    transition_active   <= 1'b0;
                    slide_offset        <= 10'd0;
                    slide_step          <= 5'd0;
                    end_hold            <= 1'b0;
                end else if (slide_step >= 5'd15) begin
                    slide_step   <= 5'd16;
                    slide_offset <= 10'd640;
                    end_hold     <= 1'b1;
                end else begin
                    slide_step   <= slide_step + 1'b1;
                    slide_offset <= ease_offset(slide_step + 1'b1);
                end
            end
        end
    end
end

endmodule
