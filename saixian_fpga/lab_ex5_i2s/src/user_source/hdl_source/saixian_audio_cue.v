module saixian_audio_cue #(
    parameter integer CLK_FREQ_HZ    = 25_000_000,
    parameter integer SAMPLE_RATE_HZ = 48_000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  cue_event,
    output reg         audio_valid,
    output reg  [23:0] audio_left,
    output reg  [23:0] audio_right,
    output reg  [7:0]  audio_level
);

localparam CUE_COUNT  = 4'd1;
localparam CUE_START  = 4'd2;
localparam CUE_PAUSE  = 4'd3;
localparam CUE_RESUME = 4'd4;
localparam CUE_FINISH = 4'd5;

reg [31:0] sample_acc;
reg [31:0] phase_acc;
reg [31:0] phase_inc;
reg [16:0] samples_left;
reg [16:0] segment_samples;
reg [2:0]  segment;
reg [3:0]  active_cue;
reg signed [23:0] pcm;
reg [7:0] envelope;
reg [7:0] peak_hold;
reg [10:0] peak_decay_count;
reg [32:0] sample_sum;
wire [16:0] attack_samples = segment_samples - samples_left;

wire sample_tick = (sample_sum >= CLK_FREQ_HZ);
wire signed [23:0] triangle = phase_acc[31] ?
                              -$signed({1'b0, phase_acc[30:8]}) :
                               $signed({1'b0, phase_acc[30:8]});

function [31:0] frequency_increment;
    input [15:0] hz;
    begin
        case (hz)
            16'd330 : frequency_increment = 32'd29527900;
            16'd440 : frequency_increment = 32'd39370534;
            16'd660 : frequency_increment = 32'd59055800;
            16'd880 : frequency_increment = 32'd78741067;
            16'd990 : frequency_increment = 32'd88583700;
            16'd1320: frequency_increment = 32'd118111600;
            default: frequency_increment = 32'd0;
        endcase
    end
endfunction

task start_segment;
    input [15:0] hz;
    input [16:0] count;
    begin
        phase_inc       <= frequency_increment(hz);
        samples_left    <= count;
        segment_samples <= count;
        phase_acc       <= 32'd0;
    end
endtask

always @* begin
    sample_sum = {1'b0, sample_acc} + SAMPLE_RATE_HZ;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sample_acc       <= 32'd0;
        phase_acc        <= 32'd0;
        phase_inc        <= 32'd0;
        samples_left     <= 17'd0;
        segment_samples  <= 17'd0;
        segment           <= 3'd0;
        active_cue        <= 4'd0;
        pcm               <= 24'sd0;
        audio_valid       <= 1'b0;
        audio_left        <= 24'd0;
        audio_right       <= 24'd0;
        envelope          <= 8'd0;
        audio_level       <= 8'd0;
        peak_hold         <= 8'd0;
        peak_decay_count  <= 11'd0;
    end else begin
        audio_valid <= 1'b0;

        if (cue_event != 4'd0) begin
            active_cue <= cue_event;
            segment    <= 3'd0;
            case (cue_event)
                CUE_COUNT : start_segment(16'd880, 17'd5760);   // 120 ms
                CUE_START : start_segment(16'd1320,17'd28800);  // 600 ms
                CUE_PAUSE : start_segment(16'd440, 17'd7200);   // first low pulse
                CUE_RESUME: start_segment(16'd660, 17'd7200);   // rising pair
                CUE_FINISH: start_segment(16'd440, 17'd12000);  // falling pair
                default   : start_segment(16'd0,   17'd1);
            endcase
        end

        else if (sample_tick) begin
            sample_acc  <= sample_sum - CLK_FREQ_HZ;
            audio_valid <= 1'b1;

            if (samples_left != 0 && phase_inc != 0) begin
                phase_acc <= phase_acc + phase_inc;
                samples_left <= samples_left - 17'd1;

                if (samples_left < 17'd480)
                    envelope <= samples_left[8:1];
                else if (attack_samples < 17'd480)
                    envelope <= attack_samples[8:1];
                else
                    envelope <= 8'd220;

                pcm <= (triangle >>> 8) * $signed({1'b0,envelope});
                audio_left  <= pcm;
                audio_right <= pcm;
            end else begin
                pcm         <= 24'sd0;
                audio_left  <= 24'd0;
                audio_right <= 24'd0;
                envelope    <= 8'd0;

                case (active_cue)
                    CUE_PAUSE: begin
                        if (segment == 3'd0) begin
                            segment <= 3'd1;
                            start_segment(16'd0, 17'd4800);
                        end else if (segment == 3'd1) begin
                            segment <= 3'd2;
                            start_segment(16'd440, 17'd7200);
                        end else active_cue <= 4'd0;
                    end
                    CUE_RESUME: begin
                        if (segment == 3'd0) begin
                            segment <= 3'd1;
                            start_segment(16'd0, 17'd2400);
                        end else if (segment == 3'd1) begin
                            segment <= 3'd2;
                            start_segment(16'd990, 17'd9600);
                        end else active_cue <= 4'd0;
                    end
                    CUE_FINISH: begin
                        if (segment == 3'd0) begin
                            segment <= 3'd1;
                            start_segment(16'd0, 17'd2400);
                        end else if (segment == 3'd1) begin
                            segment <= 3'd2;
                            start_segment(16'd330, 17'd31200);
                        end else active_cue <= 4'd0;
                    end
                    default: active_cue <= 4'd0;
                endcase
            end

            if (pcm[23] ? ((~pcm[22:15]) + 8'd1) > peak_hold : pcm[22:15] > peak_hold)
                peak_hold <= pcm[23] ? ((~pcm[22:15]) + 8'd1) : pcm[22:15];
        end else begin
            sample_acc <= sample_sum[31:0];
        end

        if (peak_decay_count == 11'd1999) begin
            peak_decay_count <= 11'd0;
            if (peak_hold != 0)
                peak_hold <= peak_hold - 8'd1;
            audio_level <= peak_hold;
        end else begin
            peak_decay_count <= peak_decay_count + 11'd1;
        end
    end
end

endmodule
