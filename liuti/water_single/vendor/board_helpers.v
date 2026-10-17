module saixian_pcm_player(
    input  wire        clk,
    input  wire        rst,
    input  wire        play_enable,
    input  wire        sample_tick,
    input  wire        fifo_empty,
    input  wire [31:0] fifo_data,
    input  wire        fifo_valid,
    output reg         fifo_read,
    output reg  [23:0] audio_left,
    output reg  [23:0] audio_right,
    output reg  [7:0]  audio_level,
    output reg         audio_active,
    output reg [31:0] underrun_count,
    output reg  [4:0]  spectrum_tone_bin
);

reg read_pending;
reg sample_ready;
reg [31:0] sample_word;
reg last_sign;
reg [9:0] zero_period;
reg [12:0] silent_sample_count;
reg [6:0] level_decay_count;
wire [15:0] left_abs = sample_word[15] ? (~sample_word[15:0] + 16'd1) : sample_word[15:0];
wire [7:0] sample_level = left_abs[15] ? 8'hff : left_abs[14:7];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        underrun_count <= 0;
        fifo_read <= 1'b0;
        read_pending <= 1'b0;
        sample_ready <= 1'b0;
        sample_word <= 32'd0;
        audio_left <= 24'd0;
        audio_right <= 24'd0;
        audio_level <= 8'd0;
        audio_active <= 1'b0;
        spectrum_tone_bin <= 5'd0;
        last_sign <= 1'b0;
        zero_period <= 10'd0;
        silent_sample_count <= 13'd0;
        level_decay_count <= 7'd0;
    end else begin
        fifo_read <= 1'b0;

        if (play_enable && !sample_ready && !read_pending && !fifo_empty) begin
            fifo_read <= 1'b1;
            read_pending <= 1'b1;
        end
        if (fifo_valid) begin
            sample_word <= fifo_data;
            sample_ready <= 1'b1;
            read_pending <= 1'b0;
        end

        // Pause at the current stereo sample while an event is active.  The
        // prefetched word is retained, so returning to the carousel resumes
        // cleanly instead of restarting the file or draining it silently.
        if (!play_enable) begin
            audio_left <= 24'd0;
            audio_right <= 24'd0;
            audio_level <= 8'd0;
            audio_active <= 1'b0;
            zero_period <= 10'd0;
            silent_sample_count <= 13'd0;
            level_decay_count <= 7'd0;
        end else if (sample_tick) begin
            if (sample_ready) begin
                // The TF file is stereo signed-16 little-endian.  Left shift
                // by eight to match the HDMI core's signed 24-bit interface.
                audio_left <= {sample_word[15:0],8'd0};
                audio_right <= {sample_word[31:16],8'd0};
                sample_ready <= 1'b0;

                // Peak-style envelope: attack immediately, then release by
                // one level every 2 ms.  PCM zero crossings therefore change
                // individual bar heights without blanking the whole display.
                if (sample_level > audio_level) begin
                    audio_level <= sample_level;
                    level_decay_count <= 7'd0;
                end else if (level_decay_count >= 7'd95) begin
                    level_decay_count <= 7'd0;
                    if (audio_level != 8'd0)
                        audio_level <= audio_level - 8'd1;
                end else begin
                    level_decay_count <= level_decay_count + 7'd1;
                end

                // Require about 100 ms of continuous near-silence before
                // declaring the source inactive.  This bridges both waveform
                // zero crossings and brief TF/FIFO service gaps.
                if (left_abs > 16'd128) begin
                    audio_active <= 1'b1;
                    silent_sample_count <= 13'd0;
                end else if (silent_sample_count < 13'd4800) begin
                    silent_sample_count <= silent_sample_count + 13'd1;
                end else begin
                    audio_active <= 1'b0;
                end

                if (zero_period != 10'h3ff)
                    zero_period <= zero_period + 10'd1;
                if ((sample_word[15] != last_sign) && (left_abs > 16'd256)) begin
                    last_sign <= sample_word[15];
                    if (zero_period >= 10'd96) spectrum_tone_bin <= 5'd1;
                    else if (zero_period >= 10'd48) spectrum_tone_bin <= 5'd3;
                    else if (zero_period >= 10'd24) spectrum_tone_bin <= 5'd6;
                    else if (zero_period >= 10'd12) spectrum_tone_bin <= 5'd11;
                    else if (zero_period >= 10'd6) spectrum_tone_bin <= 5'd18;
                    else spectrum_tone_bin <= 5'd26;
                    zero_period <= 10'd0;
                end
            end else begin
                underrun_count <= underrun_count+1'b1;
                audio_left <= 24'd0;
                audio_right <= 24'd0;
                if (level_decay_count >= 7'd95) begin
                    level_decay_count <= 7'd0;
                    if (audio_level != 8'd0)
                        audio_level <= audio_level - 8'd1;
                end else begin
                    level_decay_count <= level_decay_count + 7'd1;
                end
                if (silent_sample_count < 13'd4800)
                    silent_sample_count <= silent_sample_count + 13'd1;
                else
                    audio_active <= 1'b0;
            end
        end
    end
end

endmodule
module saixian_key_short_long #(
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer HOLD_MS = 1000
)(
    input  wire clk,
    input  wire rst,
    input  wire key_n,
    input  wire press_pulse,
    output reg  short_pulse,
    output reg  long_pulse
);
localparam integer HOLD_CYCLES = (CLK_FREQ_HZ / 1000) * HOLD_MS;
reg key_meta, key_sync;
reg press_pending, long_fired;
reg [31:0] hold_count;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        key_meta      <= 1'b1;
        key_sync      <= 1'b1;
        press_pending <= 1'b0;
        long_fired    <= 1'b0;
        hold_count    <= 32'd0;
        short_pulse   <= 1'b0;
        long_pulse    <= 1'b0;
    end else begin
        key_meta    <= key_n;
        key_sync    <= key_meta;
        short_pulse <= 1'b0;
        long_pulse  <= 1'b0;

        if (press_pulse)
            press_pending <= 1'b1;

        if (key_sync) begin
            if (press_pending && !long_fired)
                short_pulse <= 1'b1;
            press_pending <= 1'b0;
            long_fired    <= 1'b0;
            hold_count    <= 32'd0;
        end else if (!long_fired) begin
            if (hold_count >= HOLD_CYCLES - 1) begin
                long_pulse <= 1'b1;
                long_fired <= 1'b1;
            end else begin
                hold_count <= hold_count + 32'd1;
            end
        end
    end
end
endmodule
module saixian_reset_sync(
    input  wire clk,
    input  wire arst,
    output wire rst
);
    reg [2:0] sync_ff;
    always @(posedge clk or posedge arst) begin
        if (arst) sync_ff <= 3'b111;
        else      sync_ff <= {sync_ff[1:0], 1'b0};
    end
    assign rst = sync_ff[2];
endmodule
