module saixian_event_controller #(
    parameter integer CLK_FREQ_HZ = 25_000_000
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_start,
    input  wire       key_start,
    input  wire       key_pause,
    input  wire       key_end,
    input  wire [1:0] project_switch,

    output reg  [3:0] state,
    output reg  [1:0] project_id,
    output reg  [6:0] minutes,
    output reg  [5:0] seconds,
    output reg  [3:0] countdown_value,
    output reg  [3:0] cue_event,
    output wire       carousel_mode
);

localparam ST_CAROUSEL = 4'd0;
localparam ST_PREPARE  = 4'd1;
localparam ST_COUNT3   = 4'd2;
localparam ST_COUNT2   = 4'd3;
localparam ST_COUNT1   = 4'd4;
localparam ST_START    = 4'd5;
localparam ST_RUNNING  = 4'd6;
localparam ST_PAUSED   = 4'd7;
localparam ST_FINISH   = 4'd8;

localparam CUE_NONE    = 4'd0;
localparam CUE_COUNT   = 4'd1;
localparam CUE_START   = 4'd2;
localparam CUE_PAUSE   = 4'd3;
localparam CUE_RESUME  = 4'd4;
localparam CUE_FINISH  = 4'd5;

reg [24:0] second_counter;
reg        second_pending;
reg [2:0]  state_seconds;
reg        start_pending;
reg        pause_pending;
reg        end_pending;
reg [1:0]  project_sync0;
reg [1:0]  project_sync1;

assign carousel_mode = (state == ST_CAROUSEL);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_CAROUSEL;
        project_id        <= 2'd0;
        minutes           <= 7'd0;
        seconds           <= 6'd0;
        countdown_value   <= 4'd0;
        cue_event         <= CUE_NONE;
        second_counter    <= 25'd0;
        second_pending    <= 1'b0;
        state_seconds     <= 3'd0;
        start_pending     <= 1'b0;
        pause_pending     <= 1'b0;
        end_pending       <= 1'b0;
        project_sync0     <= 2'd0;
        project_sync1     <= 2'd0;
    end else begin
        project_sync0 <= project_switch;
        project_sync1 <= project_sync0;
        cue_event     <= CUE_NONE;

        if (key_start)
            start_pending <= 1'b1;
        if (key_pause)
            pause_pending <= 1'b1;
        if (key_end)
            end_pending <= 1'b1;

        if (second_counter == CLK_FREQ_HZ - 1) begin
            second_counter <= 25'd0;
            second_pending <= 1'b1;
        end else begin
            second_counter <= second_counter + 25'd1;
        end

        if (frame_start) begin
            case (state)
                ST_CAROUSEL: begin
                    minutes         <= 7'd0;
                    seconds         <= 6'd0;
                    state_seconds   <= 3'd0;
                    second_pending  <= 1'b0;
                    pause_pending   <= 1'b0;
                    end_pending     <= 1'b0;
                    if (start_pending) begin
                        state           <= ST_PREPARE;
                        project_id      <= project_sync1;
                        start_pending   <= 1'b0;
                        second_counter  <= 25'd0;
                    end
                end

                ST_PREPARE: begin
                    if (end_pending) begin
                        state         <= ST_CAROUSEL;
                        end_pending   <= 1'b0;
                        start_pending <= 1'b0;
                    end else if (start_pending || (second_pending && state_seconds == 3'd1)) begin
                        state             <= ST_COUNT3;
                        countdown_value   <= 4'd3;
                        cue_event         <= CUE_COUNT;
                        state_seconds     <= 3'd0;
                        start_pending     <= 1'b0;
                        second_pending    <= 1'b0;
                        second_counter    <= 25'd0;
                    end else if (second_pending) begin
                        state_seconds  <= state_seconds + 3'd1;
                        second_pending <= 1'b0;
                    end
                end

                ST_COUNT3: begin
                    start_pending <= 1'b0;
                    if (end_pending) begin
                        state           <= ST_CAROUSEL;
                        end_pending     <= 1'b0;
                        second_pending  <= 1'b0;
                    end else if (second_pending) begin
                        state             <= ST_COUNT2;
                        countdown_value   <= 4'd2;
                        cue_event         <= CUE_COUNT;
                        second_pending    <= 1'b0;
                    end
                end

                ST_COUNT2: begin
                    if (end_pending) begin
                        state          <= ST_CAROUSEL;
                        end_pending    <= 1'b0;
                        second_pending <= 1'b0;
                    end else if (second_pending) begin
                        state             <= ST_COUNT1;
                        countdown_value   <= 4'd1;
                        cue_event         <= CUE_COUNT;
                        second_pending    <= 1'b0;
                    end
                end

                ST_COUNT1: begin
                    if (end_pending) begin
                        state          <= ST_CAROUSEL;
                        end_pending    <= 1'b0;
                        second_pending <= 1'b0;
                    end else if (second_pending) begin
                        state             <= ST_START;
                        countdown_value   <= 4'd0;
                        cue_event         <= CUE_START;
                        second_pending    <= 1'b0;
                    end
                end

                ST_START: begin
                    if (end_pending) begin
                        state          <= ST_FINISH;
                        cue_event      <= CUE_FINISH;
                        end_pending    <= 1'b0;
                        second_pending <= 1'b0;
                        state_seconds  <= 3'd0;
                    end else if (second_pending) begin
                        state          <= ST_RUNNING;
                        minutes        <= 7'd0;
                        seconds        <= 6'd0;
                        second_pending <= 1'b0;
                    end
                end

                ST_RUNNING: begin
                    start_pending <= 1'b0;
                    if (end_pending) begin
                        state          <= ST_FINISH;
                        cue_event      <= CUE_FINISH;
                        end_pending    <= 1'b0;
                        pause_pending  <= 1'b0;
                        second_pending <= 1'b0;
                        state_seconds  <= 3'd0;
                    end else if (pause_pending) begin
                        state         <= ST_PAUSED;
                        cue_event     <= CUE_PAUSE;
                        pause_pending <= 1'b0;
                        second_counter <= 25'd0;
                        second_pending <= 1'b0;
                    end else if (second_pending) begin
                        second_pending <= 1'b0;
                        if (!((minutes == 7'd99) && (seconds == 6'd59))) begin
                            if (seconds == 6'd59) begin
                                seconds <= 6'd0;
                                minutes <= minutes + 7'd1;
                            end else begin
                                seconds <= seconds + 6'd1;
                            end
                        end
                    end
                end

                ST_PAUSED: begin
                    start_pending  <= 1'b0;
                    second_pending <= 1'b0;
                    if (end_pending) begin
                        state         <= ST_FINISH;
                        cue_event     <= CUE_FINISH;
                        end_pending   <= 1'b0;
                        pause_pending <= 1'b0;
                        state_seconds <= 3'd0;
                    end else if (pause_pending) begin
                        state         <= ST_RUNNING;
                        cue_event     <= CUE_RESUME;
                        pause_pending <= 1'b0;
                        second_counter <= 25'd0;
                    end
                end

                ST_FINISH: begin
                    start_pending <= 1'b0;
                    pause_pending <= 1'b0;
                    if (end_pending || (second_pending && state_seconds == 3'd2)) begin
                        state           <= ST_CAROUSEL;
                        state_seconds   <= 3'd0;
                        end_pending     <= 1'b0;
                        second_pending  <= 1'b0;
                    end else if (second_pending) begin
                        state_seconds  <= state_seconds + 3'd1;
                        second_pending <= 1'b0;
                    end
                end

                default: state <= ST_CAROUSEL;
            endcase
        end
    end
end

endmodule
