module top(
    input clk,
    input [3:0] key,
    input [1:0] sw,
    input hdmi_hpd,
    output [3:0] led,
    output [5:0] seg_sel,
    output [7:0] seg_data,
    output HDMI_CLK_P, output HDMI_D2_P, output HDMI_D1_P, output HDMI_D0_P,
    output HDMI_DDC_SCL, inout HDMI_DDC_SDA,
    output sd_ncs, output sd_dclk, output sd_mosi, input sd_miso,
    input hmi_uart_rx, output hmi_uart_tx
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS = 21;
parameter integer VIDEO_CLK_HZ = 75_000_000;
parameter HDMI_COMPAT_DIAGNOSTIC = 1'b0;
parameter VIDEO_PATH_TEST_PATTERN = 1'b0;
// Store two RGB565 pixels in every 32-bit SDRAM word.  The previous
// one-pixel-per-word layout needed 55.9 Mword/s at 720p60, which is more than
// the timing-clean 50 MHz SDRAM interface can deliver.
parameter [20:0] FRAME_WORDS = 21'd460800;
localparam [20:0] VGA_FRAME_WORDS = 21'd307200;
parameter [20:0] BUF0_ADDR = 21'd0;
parameter BUF1_ADDR = FRAME_WORDS;
// One 720p RGB565 frame reserved for the 100 m result route.  The two
// carousel buffers still occupy only indices 0 and 1.
localparam [20:0] SPRINT_BG_ADDR = FRAME_WORDS * 21'd2;

wire sd_card_clk, ext_mem_clk, ext_mem_clk_sft, video_clk, hdmi_5x_clk;
wire sys_pll_lock, video_pll_lock;
wire pll_locked = sys_pll_lock & video_pll_lock;
reg [22:0] por_count;
wire reset_request = ~por_count[22];
wire rst_clk, rst_sd, rst_mem, rst_video_pre, rst_hdmi;
reg rst_video;
reg [26:0] sd_startup_count;
wire sd_startup_hold = (sd_startup_count < 27'd100000000);

sys_pll u_sys_pll(.refclk(clk), .clk0_out(sd_card_clk), .clk1_out(ext_mem_clk), .clk2_out(ext_mem_clk_sft), .locked(sys_pll_lock), .reset(1'b0));
video_pll u_video_pll(.refclk(clk), .clk0_out(video_clk), .clk1_out(hdmi_5x_clk), .locked(video_pll_lock), .reset(1'b0));

always @(posedge clk or negedge pll_locked) begin
    if (!pll_locked) por_count <= 0;
    else if (!por_count[22]) por_count <= por_count + 1'b1;
end

// Assert every domain immediately if either PLL loses lock, then release only
// after three clean edges of that destination clock.  This avoids recovery/
// removal paths from the 50 MHz power-on counter into unrelated clock domains.
saixian_reset_sync u_rst_clk  (.clk(clk),          .arst(reset_request), .rst(rst_clk));
saixian_reset_sync u_rst_sd   (.clk(sd_card_clk),  .arst(reset_request), .rst(rst_sd));
saixian_reset_sync u_rst_mem  (.clk(ext_mem_clk),  .arst(reset_request), .rst(rst_mem));
saixian_reset_sync u_rst_video(.clk(video_clk),    .arst(reset_request), .rst(rst_video_pre));
saixian_reset_sync u_rst_hdmi (.clk(hdmi_5x_clk),  .arst(reset_request), .rst(rst_hdmi));

// Release the high-fanout asynchronous video reset on the falling edge.
// It is still asserted immediately, while the following rising edge has a
// half-cycle of recovery/removal margin for pixel-domain registers.
always @(negedge video_clk or posedge reset_request) begin
    if (reset_request) rst_video <= 1'b1;
    else               rst_video <= rst_video_pre;
end

// Give an already-inserted TF card one full second to reach stable power before
// starting SPI initialization. The HDMI boot animation remains active.
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd)
        sd_startup_count <= 27'd0;
    else if (sd_startup_hold)
        sd_startup_count <= sd_startup_count + 27'd1;
end

wire key1_press, key2_press, key3_press, key4_press;
saixian_key_debounce #(.CLK_FREQ_HZ(VIDEO_CLK_HZ),.DEBOUNCE_MS(20)) u_key1(.clk(video_clk),.rst(rst_video),.key_n(key[0]),.press_pulse(key1_press));
saixian_key_debounce #(.CLK_FREQ_HZ(VIDEO_CLK_HZ),.DEBOUNCE_MS(20)) u_key2(.clk(video_clk),.rst(rst_video),.key_n(key[1]),.press_pulse(key2_press));
saixian_key_debounce #(.CLK_FREQ_HZ(VIDEO_CLK_HZ),.DEBOUNCE_MS(20)) u_key3(.clk(video_clk),.rst(rst_video),.key_n(key[2]),.press_pulse(key3_press));
saixian_key_debounce #(.CLK_FREQ_HZ(VIDEO_CLK_HZ),.DEBOUNCE_MS(20)) u_key4(.clk(video_clk),.rst(rst_video),.key_n(key[3]),.press_pulse(key4_press));

// In carousel mode K2 selects a winner without changing the animation itself:
// release before one second selects blue; reaching one second selects red once.
wire key2_result_short_press, key2_result_long_press;
saixian_key_short_long #(.CLK_FREQ_HZ(VIDEO_CLK_HZ),.HOLD_MS(1000)) u_key2_result_press(
    .clk(video_clk),.rst(rst_video),.key_n(key[1]),.press_pulse(key2_press),
    .short_pulse(key2_result_short_press),.long_pulse(key2_result_long_press)
);

// K4 short release advances a photo; holding for one second changes music.
localparam integer KEY4_AUDIO_HOLD_CYCLES = VIDEO_CLK_HZ;
reg key4_meta, key4_sync, key4_audio_fired, key4_short_pending;
reg [26:0] key4_hold_count;
reg key4_short_pulse;
wire key4_audio_long_press = !key4_sync && !key4_audio_fired &&
                              (key4_hold_count >= KEY4_AUDIO_HOLD_CYCLES - 1);
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        key4_meta <= 1'b1; key4_sync <= 1'b1;
        key4_audio_fired <= 1'b0; key4_short_pending <= 1'b0;
        key4_short_pulse <= 1'b0; key4_hold_count <= 27'd0;
    end else begin
        key4_meta <= key[3];
        key4_sync <= key4_meta;
        key4_short_pulse <= 1'b0;
        if (key4_press) key4_short_pending <= 1'b1;
        if (key4_sync) begin
            if (key4_short_pending && !key4_audio_fired)
                key4_short_pulse <= 1'b1;
            key4_short_pending <= 1'b0;
            key4_hold_count <= 27'd0;
            key4_audio_fired <= 1'b0;
        end else if (!key4_audio_fired) begin
            if (key4_hold_count < KEY4_AUDIO_HOLD_CYCLES)
                key4_hold_count <= key4_hold_count + 1'b1;
            if (key4_audio_long_press)
                key4_audio_fired <= 1'b1;
        end
    end
end

wire [1:0] project_select;
saixian_switch_filter #(.CLK_FREQ_HZ(VIDEO_CLK_HZ),.FILTER_MS(20)) u_project_switch(
    .clk(video_clk),.rst(rst_video),.switch_in(sw),.switch_out(project_select)
);

wire hs0, vs0, de0, hs, vs, de;
wire video_read_req, video_read_req_ack, video_read_en;
wire video_read_empty, video_underflow, display_valid;
wire [31:0] video_read_data;
wire [23:0] video_rgb_raw;
wire [10:0] pixel_x;
wire [9:0] pixel_y;
wire frame_tick;

video_timing_data u_timing(.video_clk(video_clk),.rst(rst_video),.read_req(video_read_req),.read_req_ack(video_read_req_ack),.hs(hs0),.vs(vs0),.de(de0));
video_delay u_delay(.video_clk(video_clk),.rst(rst_video),.read_en(video_read_en),.read_data(video_read_data),
    .read_empty(video_read_empty),.display_valid(display_valid),.underflow_latched(video_underflow),
    .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(video_rgb_raw));
saixian_video_tracker u_tracker(.clk(video_clk),.rst(rst_video),.vs(vs),.de(de),.x(pixel_x),.y(pixel_y),.frame_tick(frame_tick));

wire hmi_start_pulse, hmi_pause_pulse, hmi_finish_pulse;
wire hmi_pause_set, hmi_resume, hmi_page_notify; wire [2:0] hmi_page_id;
wire hmi_prev_pulse, hmi_next_pulse, hmi_music_next;
wire hmi_result_blue, hmi_result_red, hmi_result_sprint, hmi_result_stop;
wire hmi_setting_valid, hmi_reset_defaults, hmi_frame_error;
wire [2:0] hmi_setting_id;
wire [7:0] hmi_setting_value;
saixian_hmi_uart #(.CLK_FREQ_HZ(VIDEO_CLK_HZ),.BAUD_RATE(115_200)) u_hmi_uart(
    .clk(video_clk),.rst(rst_video),.uart_rx(hmi_uart_rx),
    .start_pulse(hmi_start_pulse),.pause_pulse(hmi_pause_pulse),
    .pause_set_pulse(hmi_pause_set),.resume_pulse(hmi_resume),.page_id(hmi_page_id),.page_notify_pulse(hmi_page_notify),
    .music_next_pulse(hmi_music_next),.finish_pulse(hmi_finish_pulse),.prev_pulse(hmi_prev_pulse),.next_pulse(hmi_next_pulse),
    .result_blue_pulse(hmi_result_blue),.result_red_pulse(hmi_result_red),
    .result_sprint_pulse(hmi_result_sprint),.result_stop_pulse(hmi_result_stop),
    .setting_valid(hmi_setting_valid),.setting_id(hmi_setting_id),.setting_value(hmi_setting_value),
    .reset_defaults_pulse(hmi_reset_defaults),.frame_error_pulse(hmi_frame_error)
);
wire [3:0] event_state;
wire [1:0] project_id;
wire [6:0] minutes;
wire [5:0] seconds;
wire [3:0] countdown_value, cue_event;
wire carousel_mode;
wire battle_busy;
wire sprint_result_active;
wire carousel_play = carousel_mode && !battle_busy;
wire settings_mode;
wire [2:0] setting_item;
wire [3:0] volume_setting, brightness_setting, contrast_setting, saturation_setting;
wire [1:0] sharpness_setting;
wire invert_setting, vintage_setting;
wire [1:0] enhancement_setting;
wire [7:0] audio_level;
wire [2:0] audio_track_count_sd;
reg [2:0] audio_track_count_sync0, audio_track_count_sync1;
reg [2:0] audio_track_index;
reg audio_track_toggle;
reg [3:0] audio_fifo_flush_count;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        audio_track_count_sync0 <= 0; audio_track_count_sync1 <= 0;
        audio_track_index <= 0; audio_track_toggle <= 0;
        audio_fifo_flush_count <= 0;
    end else begin
        audio_track_count_sync0 <= audio_track_count_sd;
        audio_track_count_sync1 <= audio_track_count_sync0;
        if (audio_fifo_flush_count != 0)
            audio_fifo_flush_count <= audio_fifo_flush_count - 1'b1;
        if ((key4_audio_long_press || hmi_music_next) && carousel_play && !settings_mode &&
            audio_track_count_sync1 > 1) begin
            if (audio_track_index >= audio_track_count_sync1 - 1'b1)
                audio_track_index <= 0;
            else audio_track_index <= audio_track_index + 1'b1;
            audio_track_toggle <= ~audio_track_toggle;
            audio_fifo_flush_count <= 4'd15;
        end
    end
end

saixian_settings_controller #(.CLK_FREQ_HZ(VIDEO_CLK_HZ)) u_settings(
    .clk(video_clk),.rst(rst_video),.carousel_mode(carousel_play),
    .key_next_item(key1_press),.key_decrease(key2_press),
    .key_enter_exit(key3_press),.key_increase(key4_short_pulse),
    .hmi_setting_valid(hmi_setting_valid),.hmi_setting_id(hmi_setting_id),
    .hmi_setting_value(hmi_setting_value),.hmi_reset_defaults(hmi_reset_defaults),
    .settings_mode(settings_mode),.setting_item(setting_item),
    .volume_setting(volume_setting),.brightness_setting(brightness_setting),
    .contrast_setting(contrast_setting),.saturation_setting(saturation_setting),
    .sharpness_setting(sharpness_setting),
    .invert_setting(invert_setting),.vintage_setting(vintage_setting),
    .enhancement_setting(enhancement_setting)
);

saixian_event_controller #(.CLK_FREQ_HZ(VIDEO_CLK_HZ)) u_event(
    .clk(video_clk),.rst(rst_video),.frame_start(frame_tick),
    .key_start(((key1_press & ~settings_mode) | hmi_start_pulse) & ~battle_busy),
    .key_pause((key2_press & ~settings_mode) | hmi_pause_pulse |
        (hmi_pause_set && event_state == 4'd6) | (hmi_resume && event_state == 4'd7)),
    .key_end((key3_press & ~settings_mode) | hmi_finish_pulse),.project_switch(project_select),
    .state(event_state),.project_id(project_id),.minutes(minutes),.seconds(seconds),
    .countdown_value(countdown_value),.cue_event(cue_event),.carousel_mode(carousel_mode)
);

// Constant-speed left-to-right marquee phase.  Phase 0 places the
// 224-pixel headline just left of the screen; phase 864 just clears the right.
reg [9:0] ticker_x;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video)
        ticker_x <= 10'd0;
    else if (!carousel_mode || settings_mode)
        ticker_x <= 10'd0;
    else if (frame_tick) begin
        if (ticker_x >= 10'd864)
            ticker_x <= 10'd0;
        else
            ticker_x <= ticker_x + 10'd1;
    end
end

// Rotate the boot indicator at 10 steps per second. display_valid is asserted
// only after the card scan has completed and the first full frame has reached
// SDRAM, so the animation covers both discovery and initial image loading.
reg [2:0] loading_phase;
reg [2:0] loading_frame_div;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video || display_valid) begin
        loading_phase     <= 3'd0;
        loading_frame_div <= 3'd0;
    end else if (frame_tick) begin
        if (loading_frame_div == 3'd5) begin
            loading_frame_div <= 3'd0;
            loading_phase     <= loading_phase + 1'b1;
        end else begin
            loading_frame_div <= loading_frame_div + 1'b1;
        end
    end
end

reg prev_req_toggle, next_req_toggle;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin prev_req_toggle <= 0; next_req_toggle <= 0; end
    else if (carousel_play && !settings_mode) begin
        // K2 now launches the victory animation in carousel mode.  The HMI
        // previous-image command remains available.
        if (hmi_prev_pulse) prev_req_toggle <= ~prev_req_toggle;
        if (key4_short_pulse | hmi_next_pulse) next_req_toggle <= ~next_req_toggle;
    end
end

wire [3:0] sd_state_code;
wire sd_init_done, scan_done;
wire [2:0] image_count, sd_error;
reg sd_ready_ff1,sd_ready_ff2;
wire startup_initializing_video;
wire sprint_background_ready_sd;
reg sprint_background_ready_meta, sprint_background_ready_video;
wire sprint_read_enabled = sprint_result_active && sprint_background_ready_video;
wire [15:0] source_width_sd, source_height_sd;
reg [15:0] source_width_sync0, source_width_sync1;
reg [15:0] source_height_sync0, source_height_sync1;
reg [15:0] source_width_seen, source_height_seen;
reg [35:0] width_bcd_shift, height_bcd_shift;
reg [15:0] source_width_bcd, source_height_bcd;
reg [4:0] bcd_count;
reg bcd_busy;

function [35:0] bcd_add3;
    input [35:0] value;
    reg [35:0] adjusted;
    begin
        adjusted = value;
        if (adjusted[19:16] >= 5) adjusted[19:16] = adjusted[19:16] + 3;
        if (adjusted[23:20] >= 5) adjusted[23:20] = adjusted[23:20] + 3;
        if (adjusted[27:24] >= 5) adjusted[27:24] = adjusted[27:24] + 3;
        if (adjusted[31:28] >= 5) adjusted[31:28] = adjusted[31:28] + 3;
        if (adjusted[35:32] >= 5) adjusted[35:32] = adjusted[35:32] + 3;
        bcd_add3 = adjusted;
    end
endfunction

wire [35:0] width_bcd_next = bcd_add3(width_bcd_shift) << 1;
wire [35:0] height_bcd_next = bcd_add3(height_bcd_shift) << 1;
reg [2:0] sd_error_sync0, sd_error_sync1;
wire frame_ready_toggle;
wire [1:0] ready_buf_idx, write_buf_idx, active_buf_idx, slide_new_buf_idx;
wire frame_commit_toggle, transition_active, ready_slide_right, slide_right;
wire [10:0] slide_offset;
wire [5:0] transition_level;
wire [2:0] transition_mode;
wire sd_card_write_req, sd_card_write_req_ack;
wire sd_card_write_en_raw;
wire [31:0] sd_card_write_data_raw;
reg sd_card_write_en;
reg [31:0] sd_card_write_data;
reg pack_half;
reg [15:0] pack_first_pixel;
wire write_vga_sd, buffer0_vga_sd, buffer1_vga_sd;
wire frame_write_finish;
reg frame_write_toggle_mem;
wire write_fifo_full;
reg write_overflow_latched;
wire audio_pcm_we_sd;
wire [31:0] audio_pcm_word_sd;
wire audio_file_found_sd;
wire [8:0] audio_fifo_wrusedw;

function [15:0] rgb888_to_rgb565;
    input [31:0] pixel;
    begin
        rgb888_to_rgb565 = {pixel[31:27],pixel[23:18],pixel[15:11]};
    end
endfunction

// BMP reader emits RGB888, one pixel per valid pulse.  Pack adjacent pixels
// before the asynchronous write FIFO so SDRAM traffic is halved while the
// framebuffer remains full 1280x720 spatial resolution.
always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd) begin
        pack_half <= 1'b0;
        pack_first_pixel <= 16'd0;
        sd_card_write_en <= 1'b0;
        sd_card_write_data <= 32'd0;
    end else if (sd_card_write_req) begin
        pack_half <= 1'b0;
        sd_card_write_en <= 1'b0;
    end else begin
        sd_card_write_en <= 1'b0;
        if (sd_card_write_en_raw) begin
            if (write_vga_sd) begin
                sd_card_write_data <= {2{rgb888_to_rgb565(sd_card_write_data_raw)}};
                sd_card_write_en <= 1'b1;
                pack_half <= 1'b0;
            end else if (!pack_half) begin
                pack_first_pixel <= rgb888_to_rgb565(sd_card_write_data_raw);
                pack_half <= 1'b1;
            end else begin
                sd_card_write_data <= {pack_first_pixel,rgb888_to_rgb565(sd_card_write_data_raw)};
                sd_card_write_en <= 1'b1;
                pack_half <= 1'b0;
            end
        end
    end
end

always @(posedge sd_card_clk or posedge rst_sd) begin
    if (rst_sd)
        write_overflow_latched <= 1'b0;
    else if (sd_card_write_en && write_fifo_full)
        write_overflow_latched <= 1'b1;
end

always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem) frame_write_toggle_mem <= 0;
    else if (frame_write_finish) frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        source_width_seen <= 0; source_height_seen <= 0;
        width_bcd_shift <= 0; height_bcd_shift <= 0;
        source_width_bcd <= 0; source_height_bcd <= 0;
        bcd_count <= 0; bcd_busy <= 0;
    end else if (!bcd_busy &&
                 ((source_width_sync1 != source_width_seen) ||
                  (source_height_sync1 != source_height_seen))) begin
        source_width_seen <= source_width_sync1;
        source_height_seen <= source_height_sync1;
        width_bcd_shift <= {20'd0,source_width_sync1};
        height_bcd_shift <= {20'd0,source_height_sync1};
        bcd_count <= 0;
        bcd_busy <= 1;
    end else if (bcd_busy) begin
        width_bcd_shift <= width_bcd_next;
        height_bcd_shift <= height_bcd_next;
        if (bcd_count == 5'd15) begin
            source_width_bcd <= width_bcd_next[31:16];
            source_height_bcd <= height_bcd_next[31:16];
            bcd_busy <= 0;
        end else begin
            bcd_count <= bcd_count + 1'b1;
        end
    end
end

// Search the first 256 MiB of the card. Files copied to a fragmented or
// previously-used FAT volume are often allocated beyond the former 64 MiB
// window even when only five images are visible in the directory.
// Five full-length AUD tracks plus six BMPs can exceed the former 256 MiB
// raw-sector search window if FAT32 places them after a free-space gap.
sd_card_bmp #(.CLK_FREQ_HZ(100_000_000),.SCAN_START_SECTOR(0),.SCAN_MAX_SECTOR(1048575),.SCAN_TARGET_COUNT(6)) u_sd_bmp(
    .clk(sd_card_clk),.rst(rst_sd | sd_startup_hold),.prev_req_toggle(prev_req_toggle),.next_req_toggle(next_req_toggle),
    .carousel_mode(carousel_play && !settings_mode),.display_commit_toggle(frame_commit_toggle),.state_code(sd_state_code),
    .sd_init_done_o(sd_init_done),.scan_done_o(scan_done),.image_count(image_count),.error_code(sd_error),
    .source_width(source_width_sd),.source_height(source_height_sd),
    .frame_ready_toggle(frame_ready_toggle),.ready_buf_idx(ready_buf_idx),.ready_slide_right(ready_slide_right),.write_buf_idx(write_buf_idx),
    .write_vga(write_vga_sd),.buffer0_vga(buffer0_vga_sd),.buffer1_vga(buffer1_vga_sd),
    .sprint_background_ready(sprint_background_ready_sd),
    .bmp_width(16'd1280),.bmp_height(16'd720),.write_finish_toggle(frame_write_toggle_mem),
    .write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),.write_en(sd_card_write_en_raw),.write_data(sd_card_write_data_raw),
    .audio_fifo_wrusedw(audio_fifo_wrusedw),.audio_pcm_we(audio_pcm_we_sd),
    .audio_pcm_word(audio_pcm_word_sd),.audio_found_o(audio_file_found_sd),
    .audio_track_index(audio_track_index),.audio_track_toggle(audio_track_toggle),.audio_track_count_o(audio_track_count_sd),
    .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso)
);

saixian_transition u_transition(
    .clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),.frame_ready_toggle(frame_ready_toggle),.ready_buf_idx(ready_buf_idx),
    .ready_slide_right(ready_slide_right),.active_buf_idx(active_buf_idx),.slide_new_buf_idx(slide_new_buf_idx),
    .frame_commit_toggle(frame_commit_toggle),.display_valid(display_valid),.transition_active(transition_active),
    .transition_mode(transition_mode),.slide_offset(slide_offset),.slide_right(slide_right),.transition_level(transition_level)
);

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        sd_error_sync0 <= 0; sd_error_sync1 <= 0;
        sd_ready_ff1<=0;sd_ready_ff2<=0;
        source_width_sync0 <= 0; source_width_sync1 <= 0;
        source_height_sync0 <= 0; source_height_sync1 <= 0;
        sprint_background_ready_meta <= 0; sprint_background_ready_video <= 0;
    end else begin
        sd_error_sync0 <= sd_error; sd_error_sync1 <= sd_error_sync0;
        sd_ready_ff1<=sd_init_done;
        sd_ready_ff2<=sd_ready_ff1;
        source_width_sync0 <= source_width_sd; source_width_sync1 <= source_width_sync0;
        source_height_sync0 <= source_height_sd; source_height_sync1 <= source_height_sync0;
        sprint_background_ready_meta <= sprint_background_ready_sd;
        sprint_background_ready_video <= sprint_background_ready_meta;
    end
end

wire Sdr_init_done, Sdr_init_ref_vld, Sdr_busy;
wire App_rd_en, Sdr_rd_en, App_wr_en;
wire [ADDR_BITS-1:0] App_rd_addr, App_wr_addr;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout, App_wr_din;
wire [3:0] App_wr_dm;

frame_read_write #(.WRITE_V_FLIP(1),.FRAME_WIDTH(640),.FRAME_HEIGHT(720)) u_frame_rw(
    .mem_clk(ext_mem_clk),.rst(rst_mem),.Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
    .App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),
    .read_clk(video_clk),.read_req(video_read_req),.read_req_ack(video_read_req_ack),.read_finish(),
    .read_addr_0(BUF0_ADDR),.read_addr_1(BUF1_ADDR),.read_addr_2(SPRINT_BG_ADDR),.read_addr_3(21'd0),
    .read_addr_index(sprint_read_enabled ? 2'd2 : active_buf_idx),
    .read_len(FRAME_WORDS),.read_en(video_read_en),.read_data(video_read_data),.read_fifo_empty(video_read_empty),
    .slide_active(transition_active && !sprint_read_enabled),.slide_old_index(active_buf_idx),.slide_new_index(slide_new_buf_idx),
    .slide_offset({1'b0,slide_offset[10:1]}),.slide_right(slide_right),.transition_mode(transition_mode),
    .buffer0_vga(buffer0_vga_sd),.buffer1_vga(buffer1_vga_sd),
    .App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_din(App_wr_din),.App_wr_dm(App_wr_dm),
    .write_clk(sd_card_clk),.write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),.write_finish(frame_write_finish),
    .write_addr_0(BUF0_ADDR),.write_addr_1(BUF1_ADDR),.write_addr_2(SPRINT_BG_ADDR),.write_addr_3(21'd0),.write_addr_index(write_buf_idx),
    .write_len(write_vga_sd ? VGA_FRAME_WORDS : FRAME_WORDS),.write_vga(write_vga_sd),
    .write_en(sd_card_write_en),.write_data(sd_card_write_data),
    .write_fifo_full(write_fifo_full)
);

sdram u_sdram(.Clk(ext_mem_clk),.Clk_sft(ext_mem_clk_sft),.Rst(rst_mem),.Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),.App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),
    .App_wr_dm(App_wr_dm),.App_wr_din(App_wr_din),.App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),
    .Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout));

wire audio_valid;
wire cue_audio_valid;
wire [23:0] cue_audio_left, cue_audio_right;
wire [7:0] cue_audio_level;
wire cue_busy;
wire cue_spectrum_active;
wire [4:0] cue_spectrum_tone_bin;
wire [23:0] bg_audio_left, bg_audio_right;
wire [7:0] bg_audio_level;
wire bg_audio_active;
wire [4:0] bg_spectrum_tone_bin;
reg finish_cue_seen;
reg [26:0] bgm_resume_count;
reg bgm_resume_ready;
// Resume exactly one second after the complete finish cue, including its
// intentional inter-tone silence, has ended.  ST_FINISH remains active long
// enough for this delay before the controller returns to the carousel.
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        finish_cue_seen <= 1'b0;
        bgm_resume_count <= 27'd0;
        bgm_resume_ready <= 1'b0;
    end else if (event_state != 4'd8) begin
        finish_cue_seen <= 1'b0;
        bgm_resume_count <= 27'd0;
        bgm_resume_ready <= 1'b0;
    end else if (!finish_cue_seen) begin
        if (cue_busy)
            finish_cue_seen <= 1'b1;
    end else if (cue_busy) begin
        bgm_resume_count <= 27'd0;
    end else if (!bgm_resume_ready) begin
        if (bgm_resume_count >= VIDEO_CLK_HZ - 1) begin
            bgm_resume_ready <= 1'b1;
            bgm_resume_count <= 27'd0;
        end else begin
            bgm_resume_count <= bgm_resume_count + 27'd1;
        end
    end
end
wire battle_de;
reg first_picture_visible;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) first_picture_visible <= 1'b0;
    // Start only after an active pixel from a committed picture has reached
    // the final output path, rather than merely finding an AUD on the card.
    else if (display_valid && battle_de) first_picture_visible <= 1'b1;
end
wire bgm_play_enable = first_picture_visible && !battle_busy &&
                      (carousel_mode | ((event_state == 4'd8) && bgm_resume_ready));
wire [23:0] audio_left_raw, audio_right_raw;
wire [7:0] audio_level_raw;
reg [23:0] audio_left_raw_q, audio_right_raw_q;
reg [7:0] audio_level_raw_q;
wire spectrum_active;
wire [4:0] spectrum_tone_bin;
wire [23:0] audio_left_data, audio_right_data;
wire acr_valid;
wire [19:0] acr_cts, acr_n;
wire [31:0] audio_fifo_dout;
wire audio_fifo_valid, audio_fifo_full, audio_fifo_empty;
wire audio_fifo_afull, audio_fifo_aempty;
wire [8:0] audio_fifo_rdusedw;
wire audio_fifo_re;
wire audio_fifo_reset = rst_sd | rst_video | ~sd_init_done | (audio_fifo_flush_count != 0);

rfifo_32_32_512 u_audio_fifo(
    .rst(audio_fifo_reset),.clkw(sd_card_clk),.clkr(video_clk),
    .we(audio_pcm_we_sd && !audio_fifo_full),.di(audio_pcm_word_sd),
    .re(audio_fifo_re),.dout(audio_fifo_dout),.valid(audio_fifo_valid),
    .full_flag(audio_fifo_full),.empty_flag(audio_fifo_empty),
    .afull(audio_fifo_afull),.aempty(audio_fifo_aempty),
    .wrusedw(audio_fifo_wrusedw),.rdusedw(audio_fifo_rdusedw)
);

saixian_audio_cue #(.CLK_FREQ_HZ(VIDEO_CLK_HZ)) u_cue(.clk(video_clk),.rst(rst_video),.cue_event(cue_event),.audio_valid(cue_audio_valid),
    .audio_left(cue_audio_left),.audio_right(cue_audio_right),.audio_level(cue_audio_level),
    .cue_busy(cue_busy),.spectrum_active(cue_spectrum_active),.spectrum_tone_bin(cue_spectrum_tone_bin));

saixian_pcm_player u_bgm_player(
    .clk(video_clk),.rst(rst_video),.play_enable(bgm_play_enable),.sample_tick(cue_audio_valid),
    .fifo_empty(audio_fifo_empty),.fifo_data(audio_fifo_dout),.fifo_valid(audio_fifo_valid),.fifo_read(audio_fifo_re),
    .audio_left(bg_audio_left),.audio_right(bg_audio_right),.audio_level(bg_audio_level),
    .audio_active(bg_audio_active),.spectrum_tone_bin(bg_spectrum_tone_bin)
);

wire signed [24:0] audio_mix_left = ($signed(bg_audio_left) >>> 1) + ($signed(cue_audio_left) >>> 1);
wire signed [24:0] audio_mix_right = ($signed(bg_audio_right) >>> 1) + ($signed(cue_audio_right) >>> 1);
assign audio_valid = cue_audio_valid;
assign audio_left_raw = cue_spectrum_active ?
                        (bg_audio_active ? audio_mix_left[23:0] : cue_audio_left) : bg_audio_left;
assign audio_right_raw = cue_spectrum_active ?
                         (bg_audio_active ? audio_mix_right[23:0] : cue_audio_right) : bg_audio_right;
assign audio_level_raw = (bg_audio_level > cue_audio_level) ? bg_audio_level : cue_audio_level;
assign spectrum_active = bg_audio_active | cue_spectrum_active;
assign spectrum_tone_bin = cue_spectrum_active ? cue_spectrum_tone_bin : bg_spectrum_tone_bin;
// One video-clock stage separates cue synthesis and volume scaling.  At 75 MHz
// this adds only 13.3 ns, far below one 48 kHz audio sample period.
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        audio_left_raw_q <= 24'd0;
        audio_right_raw_q <= 24'd0;
        audio_level_raw_q <= 8'd0;
    end else begin
        audio_left_raw_q <= audio_left_raw;
        audio_right_raw_q <= audio_right_raw;
        audio_level_raw_q <= audio_level_raw;
    end
end
saixian_audio_volume u_volume(.volume_setting(volume_setting),.audio_left_in(audio_left_raw_q),
    .audio_right_in(audio_right_raw_q),.level_in(audio_level_raw_q),.audio_left_out(audio_left_data),
    .audio_right_out(audio_right_data),.level_out(audio_level));
audio_arc_calculate #(.ACR_N(6144)) u_acr(.I_clk(video_clk),.I_rst(rst_video),.I_audio_valid(audio_valid),
    .O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));

reg [1:0] hpd_sync;
reg hpd_present, hpd_last, edid_seen, edid_failed;
reg [19:0] hpd_debounce_timer;
reg [26:0] edid_timer;
reg edid_trig;
wire edid_valid;
wire [7:0] edid_data;
wire hdmi_error = !hpd_present || edid_failed;
wire [2:0] sd_reported_error;
saixian_startup_error_policy u_startup_error_policy(
    .clk(video_clk), .rst(rst_video), .initialized(sd_ready_ff2),
    .fault(sd_error_sync1), .reported_error(sd_reported_error),
    .initializing(startup_initializing_video));
wire [2:0] error_code = (sd_reported_error != 0) ? sd_reported_error : (hdmi_error ? 3'd5 : 3'd0);

// Synchronize SD scan results before formatting serial-screen status text.
reg [2:0] hmi_image_count_ff1, hmi_image_count_ff2;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        hmi_image_count_ff1 <= 3'd0;
        hmi_image_count_ff2 <= 3'd0;
    end else begin
        hmi_image_count_ff1 <= image_count;
        hmi_image_count_ff2 <= hmi_image_count_ff1;
    end
end

wire hmi_command_sent;
reg [3:0] hmi_sent_units, hmi_sent_tens;
saixian_hmi_status_tx #(.CLK_FREQ_HZ(VIDEO_CLK_HZ), .BAUD_RATE(115_200)) u_hmi_status_tx (
    .clk(video_clk), .rst(rst_video), .image_count(hmi_image_count_ff2),
    .audio_count(audio_track_count_sync1), .error_code(error_code),
    .initializing(startup_initializing_video),
    .page_id(hmi_page_id),.refresh_request(hmi_page_notify | hmi_setting_valid | hmi_reset_defaults),.sharpness(sharpness_setting),
    .brightness(brightness_setting),.contrast(contrast_setting),.saturation(saturation_setting),
    .volume(volume_setting),.invert(invert_setting),.vintage(vintage_setting),
    .event_state(event_state),.minutes(minutes),.seconds(seconds),
    .uart_tx(hmi_uart_tx), .command_sent_pulse(hmi_command_sent)
);
// Count complete UART commands, not screen acknowledgements. The HMI project
// has no return acknowledgement for these page-local text assignments.
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        hmi_sent_units <= 4'd0;
        hmi_sent_tens <= 4'd0;
    end else if (hmi_command_sent) begin
        if (hmi_sent_units == 4'd9) begin
            hmi_sent_units <= 4'd0;
            hmi_sent_tens <= (hmi_sent_tens == 4'd9) ? 4'd0 : hmi_sent_tens + 1'b1;
        end else hmi_sent_units <= hmi_sent_units + 1'b1;
    end
end

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        hpd_sync <= 0; hpd_present <= 0; hpd_last <= 0; hpd_debounce_timer <= 0;
        edid_seen <= 0; edid_failed <= 0; edid_timer <= 0; edid_trig <= 0;
    end else begin
        hpd_sync <= {hpd_sync[0],hdmi_hpd};
        // Accept plug/unplug only after 20 ms of stable HPD.
        if (hpd_sync[1] == hpd_present)
            hpd_debounce_timer <= 0;
        else if (hpd_debounce_timer >= 20'd749_999) begin
            hpd_present <= hpd_sync[1];
            hpd_debounce_timer <= 0;
        end else
            hpd_debounce_timer <= hpd_debounce_timer + 1'b1;

        hpd_last <= hpd_present;
        edid_trig <= 0;
        if (hpd_present && !hpd_last) begin
            edid_trig <= 1; edid_seen <= 0; edid_failed <= 0; edid_timer <= 0;
        end else if (!hpd_present) begin
            edid_seen <= 0; edid_failed <= 0; edid_timer <= 0;
        end else if (edid_valid) begin
            edid_seen <= 1; edid_failed <= 0; edid_timer <= 0;
        end else if (!edid_seen && (edid_timer >= 27'd74_999_999)) begin
            // Report E05 and retry EDID every two seconds without a reboot.
            edid_failed <= 1; edid_trig <= 1; edid_timer <= 0;
        end else if (!edid_seen)
            edid_timer <= edid_timer + 1'b1;
    end
end

wire [23:0] adjusted_rgb;
wire [23:0] styled_rgb;
// Keep a single picture configuration throughout each displayed frame.
// UI commands still update immediately; rendering adopts them in blanking.
reg [3:0] brightness_frame, contrast_frame, saturation_frame;
reg [1:0] sharpness_frame;
reg invert_frame, vintage_frame;
reg [1:0] enhancement_frame;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        brightness_frame <= 4'd4; contrast_frame <= 4'd4;
        saturation_frame <= 4'd4; sharpness_frame <= 2'd1;
        invert_frame <= 1'b0; vintage_frame <= 1'b0;
        enhancement_frame <= 2'd1;
    end else if (frame_tick) begin
        brightness_frame <= brightness_setting;
        contrast_frame <= contrast_setting;
        saturation_frame <= saturation_setting;
        sharpness_frame <= sharpness_setting;
        invert_frame <= invert_setting; vintage_frame <= vintage_setting;
        enhancement_frame <= enhancement_setting;
    end
end
saixian_hmi_color_style u_hmi_style(.rgb_in(adjusted_rgb),
    .invert(invert_frame),.vintage(vintage_frame),.rgb_out(styled_rgb));
wire [23:0] enhanced_rgb;
wire enhanced_de, enhanced_vs;
wire [10:0] enhanced_x;
wire [9:0] enhanced_y;
wire [1:0] adaptive_gain;
saixian_adaptive_enhance u_enhance(
    .clk(video_clk),.rst(rst_video),.de(de),.vs(vs),.x(pixel_x),.y(pixel_y),
    .rgb_in(video_rgb_raw),.frame_tick(frame_tick),
    .statistics_enable(display_valid && !transition_active && !battle_busy),
    .mode(enhancement_frame),.strength(sharpness_frame),
    .rgb_out(enhanced_rgb),.de_out(enhanced_de),.vs_out(enhanced_vs),
    .x_out(enhanced_x),.y_out(enhanced_y),.gain_out(adaptive_gain));
saixian_picture_adjust_pipe u_picture_adjust(.clk(video_clk),.rst(rst_video),.de(enhanced_de),.x(enhanced_x),
    .rgb_in(enhanced_rgb),.brightness_setting(brightness_frame),.contrast_setting(contrast_frame),
    .saturation_setting(saturation_frame),.sharpness_setting(2'd0),.rgb_out(adjusted_rgb));

// The picture-adjust block has eight registered stages. Delay timing and
// coordinates by the same amount so every transformed pixel keeps its DE/VS
// and screen position at the higher pixel rate.
reg [7:0] adjust_de_pipe, adjust_vs_pipe;
reg [10:0] adjust_x0, adjust_x1, adjust_x2, adjust_x3, adjust_x4, adjust_x5, adjust_x6, adjust_x7;
reg [9:0]  adjust_y0, adjust_y1, adjust_y2, adjust_y3, adjust_y4, adjust_y5, adjust_y6, adjust_y7;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        adjust_de_pipe <= 8'd0;
        adjust_vs_pipe <= 8'd0;
        adjust_x0 <= 11'd0; adjust_x1 <= 11'd0; adjust_x2 <= 11'd0; adjust_x3 <= 11'd0; adjust_x4 <= 11'd0;
        adjust_y0 <= 10'd0; adjust_y1 <= 10'd0; adjust_y2 <= 10'd0; adjust_y3 <= 10'd0; adjust_y4 <= 10'd0;
        adjust_x5 <= 0; adjust_x6 <= 0; adjust_x7 <= 0;
        adjust_y5 <= 0; adjust_y6 <= 0; adjust_y7 <= 0;
    end else begin
        adjust_de_pipe <= {adjust_de_pipe[6:0],enhanced_de};
        adjust_vs_pipe <= {adjust_vs_pipe[6:0],enhanced_vs};
        adjust_x0 <= enhanced_x; adjust_x1 <= adjust_x0; adjust_x2 <= adjust_x1; adjust_x3 <= adjust_x2; adjust_x4 <= adjust_x3;
        adjust_y0 <= enhanced_y; adjust_y1 <= adjust_y0; adjust_y2 <= adjust_y1; adjust_y3 <= adjust_y2; adjust_y4 <= adjust_y3;
        adjust_x5 <= adjust_x4; adjust_x6 <= adjust_x5; adjust_x7 <= adjust_x6;
        adjust_y5 <= adjust_y4; adjust_y6 <= adjust_y5; adjust_y7 <= adjust_y6;
    end
end

wire adjusted_de = adjust_de_pipe[7];
wire adjusted_vs = adjust_vs_pipe[7];
// Scale one logical 640x480 OSD canvas over the complete 1280x720 raster.
// Header, countdown, border, progress bar and spectrum now share one renderer,
// eliminating the duplicated middle/top bands. 683/1024 approximates 2/3 and
// maps physical line 719 to logical line 479.
wire [20:0] osd_y_product = adjust_y7 * 11'd683;
reg osd_area_in;
reg [9:0] osd_x_in;
reg [8:0] osd_y_in;
reg [23:0] osd_rgb_in;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        osd_area_in <= 1'b0;
        osd_x_in <= 10'd0;
        osd_y_in <= 9'd0;
        osd_rgb_in <= 24'd0;
    end else begin
        osd_area_in <= adjusted_de;
        osd_x_in <= adjust_x7[10:1];
        osd_y_in <= osd_y_product[18:10];
        osd_rgb_in <= styled_rgb;
    end
end
wire [23:0] osd_rgb_inner;
saixian_osd_overlay u_osd(.clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),.de_i(osd_area_in),.x_i(osd_x_in),.y_i(osd_y_in),.rgb_in_i(osd_rgb_in),.display_valid(display_valid),
    .loading_phase(loading_phase),
    .state(event_state),.project_id(carousel_mode ? project_select : project_id),.minutes(minutes),.seconds(seconds),.countdown_value(countdown_value),
    .ticker_x(ticker_x),
    .source_width_bcd(source_width_bcd),.source_height_bcd(source_height_bcd),
    .error_code(error_code),.transition_active(transition_active),.transition_level(transition_level),
    .audio_level(audio_level),.spectrum_active(spectrum_active),.spectrum_tone_bin(spectrum_tone_bin),
    .settings_mode(settings_mode),.setting_item(setting_item),
    .volume_setting(volume_setting),.brightness_setting(brightness_setting),
    .contrast_setting(contrast_setting),.sharpness_setting(sharpness_setting),
    .saturation_setting(saturation_setting),.invert_setting(invert_setting),
    .vintage_setting(vintage_setting),.enhancement_setting(enhancement_setting),
    .audio_sample_valid(audio_valid),.audio_sample(audio_left_data[23:16]),
    .rgb_out(osd_rgb_inner));

// The full-screen scaler adds one registered stage before the four-stage OSD.
// Delay the bypass path by five clocks so RGB, DE, VS and coordinates remain
// pixel-aligned.
reg osd_area_q1, osd_area_q2, osd_area_q3, osd_area_q4, osd_area_q5;
reg adjusted_de_q1, adjusted_de_q2, adjusted_de_q3, adjusted_de_q4, adjusted_de_q5;
reg adjusted_vs_q1, adjusted_vs_q2, adjusted_vs_q3, adjusted_vs_q4, adjusted_vs_q5;
reg [23:0] adjusted_rgb_q1, adjusted_rgb_q2, adjusted_rgb_q3, adjusted_rgb_q4, adjusted_rgb_q5;
reg [10:0] adjust_xq1, adjust_xq2, adjust_xq3, adjust_xq4, adjust_xq5;
reg [9:0] adjust_yq1, adjust_yq2, adjust_yq3, adjust_yq4, adjust_yq5;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        osd_area_q1 <= 1'b0; osd_area_q2 <= 1'b0; osd_area_q3 <= 1'b0; osd_area_q4 <= 1'b0; osd_area_q5 <= 1'b0;
        adjusted_de_q1 <= 1'b0; adjusted_de_q2 <= 1'b0; adjusted_de_q3 <= 1'b0; adjusted_de_q4 <= 1'b0; adjusted_de_q5 <= 1'b0;
        adjusted_vs_q1 <= 1'b0; adjusted_vs_q2 <= 1'b0; adjusted_vs_q3 <= 1'b0; adjusted_vs_q4 <= 1'b0; adjusted_vs_q5 <= 1'b0;
        adjusted_rgb_q1 <= 24'd0; adjusted_rgb_q2 <= 24'd0; adjusted_rgb_q3 <= 24'd0; adjusted_rgb_q4 <= 24'd0; adjusted_rgb_q5 <= 24'd0;
        adjust_xq1 <= 11'd0; adjust_xq2 <= 11'd0; adjust_xq3 <= 11'd0; adjust_xq4 <= 11'd0; adjust_xq5 <= 11'd0;
        adjust_yq1 <= 10'd0; adjust_yq2 <= 10'd0; adjust_yq3 <= 10'd0; adjust_yq4 <= 10'd0; adjust_yq5 <= 10'd0;
    end else begin
        osd_area_q1 <= adjusted_de; osd_area_q2 <= osd_area_q1; osd_area_q3 <= osd_area_q2; osd_area_q4 <= osd_area_q3; osd_area_q5 <= osd_area_q4;
        adjusted_de_q1 <= adjusted_de; adjusted_de_q2 <= adjusted_de_q1; adjusted_de_q3 <= adjusted_de_q2; adjusted_de_q4 <= adjusted_de_q3; adjusted_de_q5 <= adjusted_de_q4;
        adjusted_vs_q1 <= adjusted_vs; adjusted_vs_q2 <= adjusted_vs_q1; adjusted_vs_q3 <= adjusted_vs_q2; adjusted_vs_q4 <= adjusted_vs_q3; adjusted_vs_q5 <= adjusted_vs_q4;
        adjusted_rgb_q1 <= styled_rgb; adjusted_rgb_q2 <= adjusted_rgb_q1; adjusted_rgb_q3 <= adjusted_rgb_q2; adjusted_rgb_q4 <= adjusted_rgb_q3; adjusted_rgb_q5 <= adjusted_rgb_q4;
        adjust_xq1 <= adjust_x7; adjust_xq2 <= adjust_xq1; adjust_xq3 <= adjust_xq2; adjust_xq4 <= adjust_xq3; adjust_xq5 <= adjust_xq4;
        adjust_yq1 <= adjust_y7; adjust_yq2 <= adjust_yq1; adjust_yq3 <= adjust_yq2; adjust_yq4 <= adjust_yq3; adjust_yq5 <= adjust_yq4;
    end
end

wire [4:0] outside_fade_rank = {adjust_xq5[2]^adjust_yq5[0], adjust_xq5[1]^adjust_yq5[2],
                                adjust_xq5[0]^adjust_yq5[1], adjust_xq5[2]^adjust_yq5[2],
                                adjust_xq5[1]^adjust_yq5[0]};
wire outside_fade_black = transition_active && (transition_mode == 3'd5) &&
                          ({1'b0,outside_fade_rank} < transition_level);
wire boot_marker = (adjust_xq5 >= 11'd592) && (adjust_xq5 < 11'd688) &&
                   (adjust_yq5 >= (10'd312 + {loading_phase,3'b000})) &&
                   (adjust_yq5 <  (10'd320 + {loading_phase,3'b000}));
wire [23:0] compat_rgb = !adjusted_de_q5 ? 24'd0 :
                          (error_code != 0 ? 24'h500008 :
                           (!display_valid ? (boot_marker ? 24'h38E8FF : 24'h081830) : adjusted_rgb_q5));
wire [23:0] full_osd_rgb = !adjusted_de_q5 ? 24'd0 :
                             (osd_area_q5 ? osd_rgb_inner :
                             ((!display_valid || (error_code != 0) || outside_fade_black) ? 24'd0 : adjusted_rgb_q5));
// Result pixels come from the dedicated frame, bypassing carousel OSD text.
wire [23:0] osd_rgb = sprint_read_enabled ?
                      (adjusted_de_q5 ? adjusted_rgb_q5 : 24'd0) :
                      (HDMI_COMPAT_DIAGNOSTIC ? compat_rgb : full_osd_rgb);

// Register RGB and timing controls together before AXI conversion.
reg [23:0] osd_rgb_pipe;
reg        de_pipe;
reg        vs_pipe;
reg [10:0] battle_x_pipe;
reg [9:0]  battle_y_pipe;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        osd_rgb_pipe <= 24'd0;
        de_pipe      <= 1'b0;
        vs_pipe       <= 1'b0;
        battle_x_pipe <= 11'd0;
        battle_y_pipe <= 10'd0;
    end else begin
        osd_rgb_pipe <= osd_rgb;
        de_pipe      <= adjusted_de_q5;
        vs_pipe       <= adjusted_vs_q5;
        battle_x_pipe <= adjust_xq5;
        battle_y_pipe <= adjust_yq5;
    end
end

// Outside a result animation, K2 short/long selects blue/red.  Once a result is
// active, either press is routed back to the original "K2 continue" input, so a
// short continue press cannot restart blue victory.  HMI direct selection,
// ranking and all animation rendering stay unchanged.
wire [23:0] battle_rgb;
wire battle_vs;
wire key2_result_continue, key2_result_blue_select, key2_result_red_select;
saixian_key2_result_router u_key2_result_router(
    .result_mode(carousel_mode & ~settings_mode),.battle_busy(battle_busy),
    .short_pulse(key2_result_short_press),.long_pulse(key2_result_long_press),
    .continue_pulse(key2_result_continue),.blue_select(key2_result_blue_select),
    .red_select(key2_result_red_select)
);
saixian_battle_result_fx u_battle_result(
    .clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),
    .trigger(key2_result_continue),
    .select_blue((hmi_result_blue & carousel_mode & ~settings_mode) | key2_result_blue_select),
    .select_red((hmi_result_red & carousel_mode & ~settings_mode) | key2_result_red_select),
    .select_sprint(hmi_result_sprint & carousel_mode & ~settings_mode),.stop(hmi_result_stop),
    .busy(battle_busy),.sprint_active(sprint_result_active),
    .sprint_background_valid(sprint_background_ready_video),
    .x_in(battle_x_pipe),.y_in(battle_y_pipe),
    .de_in(de_pipe),.vs_in(vs_pipe),.rgb_in(osd_rgb_pipe),
    .de_out(battle_de),.vs_out(battle_vs),.rgb_out(battle_rgb)
);

wire axis_s_user, axis_s_valid, axis_s_last, axis_s_ready;
wire [23:0] axis_s_data;
// Output-only diagnostic: constant gray bypasses BMP, SDRAM and picture
// processing, but retains the normal timing and HDMI transmitter chain.
wire [23:0] axis_rgb = VIDEO_PATH_TEST_PATTERN ? 24'h808080 : battle_rgb;
video_rgb_to_axis_640x480 #(.H_ACTIVE(1280)) u_axis(.I_clk(video_clk),.I_rst(rst_video),.I_vs(battle_vs),.I_de(battle_de),.I_rgb(axis_rgb),
    .O_video_user(axis_s_user),.O_video_valid(axis_s_valid),.O_video_last(axis_s_last),.O_video_data(axis_s_data));

wire [9:0] tmds_ch0_data, tmds_ch1_data, tmds_ch2_data, tmds_clk_data;
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"),.HTOTAL(1650),.HSA(40),.HFP(110),.HBP(220),.HACTIVE(1280),
    .VTOTAL(750),.VSA(5),.VFP(5),.VBP(20),.VACTIVE(720),.VIDEO_VIC(4),
    .VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(375)
) u_hdmi_tx(
    .I_pixel_clk(video_clk),.I_rst(rst_video),.I_edid_read_trig(edid_trig),.O_edid_read_valid(edid_valid),.O_edid_read_data(edid_data),
    .I_axis_s_user(axis_s_user),.I_axis_s_valid(axis_s_valid),.I_axis_s_last(axis_s_last),.I_axis_s_data(axis_s_data),.O_axis_s_ready(axis_s_ready),
    .I_audio_valid(audio_valid),.I_audio_left_data(audio_left_data),.I_audio_right_data(audio_right_data),
    .I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),.O_video_locked(),
    .O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),.O_ch0_tmds_data(tmds_ch0_data),
    .O_ch1_tmds_data(tmds_ch1_data),.O_ch2_tmds_data(tmds_ch2_data),.O_clk_tmds_data(tmds_clk_data));

hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy(.I_pixel_clk(video_clk),.I_serial_clk(hdmi_5x_clk),.I_rst(rst_hdmi),
    .I_tmds_channel_0(tmds_ch0_data),.I_tmds_channel_1(tmds_ch1_data),.I_tmds_channel_2(tmds_ch2_data),
    .I_tmds_channel_clk(tmds_clk_data),.O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),
    .O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));

// The event controller lives in the video domain. Retiming its low-rate status
// into the 50 MHz display domain avoids a direct video_clk-to-clk CDC path.
reg [2:0] error_code_clk_ff1, error_code_clk;
reg [2:0] image_count_clk_ff1, image_count_clk;
reg [3:0] event_state_clk_ff1, event_state_clk;
reg [3:0] hmi_sent_units_clk_ff1, hmi_sent_units_clk;
reg [3:0] hmi_sent_tens_clk_ff1, hmi_sent_tens_clk;
always @(posedge clk) begin
    if (rst_clk) begin
        error_code_clk_ff1 <= 3'd0;
        error_code_clk     <= 3'd0;
        image_count_clk_ff1 <= 3'd0;
        image_count_clk     <= 3'd0;
        event_state_clk_ff1 <= 4'd0;
        event_state_clk     <= 4'd0;
        hmi_sent_units_clk_ff1 <= 4'd0;
        hmi_sent_units_clk <= 4'd0;
        hmi_sent_tens_clk_ff1 <= 4'd0;
        hmi_sent_tens_clk <= 4'd0;
    end else begin
        error_code_clk_ff1 <= error_code;
        error_code_clk     <= error_code_clk_ff1;
        image_count_clk_ff1 <= image_count;
        image_count_clk     <= image_count_clk_ff1;
        event_state_clk_ff1 <= event_state;
        event_state_clk     <= event_state_clk_ff1;
        hmi_sent_units_clk_ff1 <= hmi_sent_units;
        hmi_sent_units_clk <= hmi_sent_units_clk_ff1;
        hmi_sent_tens_clk_ff1 <= hmi_sent_tens;
        hmi_sent_tens_clk <= hmi_sent_tens_clk_ff1;
    end
end

wire [6:0] seg_code;
wire [6:0] seg_image_code;
wire [6:0] seg_hmi_units_code, seg_hmi_tens_code;
seg_decoder u_seg_decode(.bin_data(error_code_clk != 0 ? {1'b0,error_code_clk} : event_state_clk),.seg_data(seg_code));
seg_decoder u_seg_image_decode(.bin_data({1'b0,image_count_clk}),.seg_data(seg_image_code));
seg_decoder u_seg_hmi_units(.bin_data(hmi_sent_units_clk),.seg_data(seg_hmi_units_code));
seg_decoder u_seg_hmi_tens(.bin_data(hmi_sent_tens_clk),.seg_data(seg_hmi_tens_code));
seg_scan u_seg(.clk(clk),.rst_n(~rst_clk),.seg_sel(seg_sel),.seg_data(seg_data),
    .seg_data_0({1'b1,seg_code}),.seg_data_1({1'b1,seg_image_code}),.seg_data_2({1'b1,seg_hmi_units_code}),
    .seg_data_3({1'b1,seg_hmi_tens_code}),.seg_data_4({1'b1,7'b1111111}),.seg_data_5({1'b1,7'b1111111}));

assign led[0] = carousel_mode;
assign led[1] = sd_init_done;
assign led[2] = hpd_present;
// LED4 indicates an E-code, video FIFO underflow, or write FIFO overflow.
assign led[3] = (error_code != 0) | video_underflow | write_overflow_latched;

endmodule

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

module saixian_key2_result_router(
    input  wire result_mode,
    input  wire battle_busy,
    input  wire short_pulse,
    input  wire long_pulse,
    output wire continue_pulse,
    output wire blue_select,
    output wire red_select
);
assign continue_pulse = result_mode && battle_busy && (short_pulse || long_pulse);
assign blue_select    = result_mode && !battle_busy && short_pulse;
assign red_select     = result_mode && !battle_busy && long_pulse;
endmodule

// Classify one active-low key press.  The debounced press pulse arms short-press
// reporting, while a synchronized raw level makes the one-second threshold
// independent of the 20 ms debounce delay.  A long press fires exactly once and
// suppresses the short pulse when the key is released.
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

module saixian_switch_filter #(
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer FILTER_MS = 20
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [1:0] switch_in,
    output reg  [1:0] switch_out
);
localparam integer FILTER_CYCLES = (CLK_FREQ_HZ / 1000) * FILTER_MS;
reg [1:0] sync0, sync1;
reg [19:0] stable_count;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        sync0        <= 2'b00;
        sync1        <= 2'b00;
        switch_out   <= 2'b00;
        stable_count <= 20'd0;
    end else begin
        sync0 <= switch_in;
        sync1 <= sync0;
        if (sync1 == switch_out)
            stable_count <= 20'd0;
        else if (stable_count >= FILTER_CYCLES - 1) begin
            switch_out   <= sync1;
            stable_count <= 20'd0;
        end else
            stable_count <= stable_count + 1'b1;
    end
end
endmodule

module saixian_settings_controller #(
    parameter integer CLK_FREQ_HZ = 25_000_000,
    parameter integer TIMEOUT_SECONDS = 60
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       carousel_mode,
    input  wire       key_next_item,
    input  wire       key_decrease,
    input  wire       key_enter_exit,
    input  wire       key_increase,
    input  wire       hmi_setting_valid,
    input  wire [2:0] hmi_setting_id,
    input  wire [7:0] hmi_setting_value,
    input  wire       hmi_reset_defaults,
    output reg        settings_mode,
    output reg [2:0]  setting_item,
    output reg [3:0]  volume_setting,
    output reg [3:0]  brightness_setting,
    output reg [3:0]  contrast_setting,
    output reg [3:0]  saturation_setting,
    output reg [1:0]  sharpness_setting,
    output reg        invert_setting,
    output reg        vintage_setting,
    output reg [1:0]  enhancement_setting
);
localparam [32:0] TIMEOUT_CYCLES = 64'd1 * CLK_FREQ_HZ * TIMEOUT_SECONDS;
reg [32:0] idle_timer;

function [3:0] quantize_percent;
    input [7:0] value;
    begin
        if      (value <= 8'd6)  quantize_percent = 4'd0;
        else if (value <= 8'd18) quantize_percent = 4'd1;
        else if (value <= 8'd31) quantize_percent = 4'd2;
        else if (value <= 8'd43) quantize_percent = 4'd3;
        else if (value <= 8'd56) quantize_percent = 4'd4;
        else if (value <= 8'd68) quantize_percent = 4'd5;
        else if (value <= 8'd81) quantize_percent = 4'd6;
        else if (value <= 8'd93) quantize_percent = 4'd7;
        else                     quantize_percent = 4'd8;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        settings_mode      <= 1'b0;
        setting_item       <= 3'd0;
        volume_setting     <= 4'd5;
        brightness_setting <= 4'd4;
        contrast_setting   <= 4'd4;
        saturation_setting <= 4'd4;
        sharpness_setting  <= 2'd1;
        invert_setting     <= 1'b0;
        vintage_setting    <= 1'b0;
        enhancement_setting <= 2'd1;
        idle_timer         <= 33'd0;
    end else if (hmi_reset_defaults) begin
        volume_setting     <= 4'd5;
        brightness_setting <= 4'd4;
        contrast_setting   <= 4'd4;
        saturation_setting <= 4'd4;
        sharpness_setting  <= 2'd1;
        invert_setting     <= 1'b0;
        vintage_setting    <= 1'b0;
        enhancement_setting <= 2'd1;
        idle_timer         <= 33'd0;
    end else if (hmi_setting_valid) begin
        idle_timer <= 33'd0;
        case (hmi_setting_id)
            3'd0: sharpness_setting  <= (hmi_setting_value > 3) ? 2'd3 : hmi_setting_value[1:0];
            3'd1: brightness_setting <= quantize_percent(hmi_setting_value);
            3'd2: contrast_setting   <= quantize_percent(hmi_setting_value);
            3'd3: saturation_setting <= quantize_percent(hmi_setting_value);
            3'd4: volume_setting     <= quantize_percent(hmi_setting_value);
            3'd5: invert_setting     <= (hmi_setting_value != 0);
            3'd6: vintage_setting    <= (hmi_setting_value != 0);
            3'd7: enhancement_setting <= (hmi_setting_value>2) ? 2'd2 : hmi_setting_value[1:0];
            default: ;
        endcase
    end else if (!carousel_mode) begin
        settings_mode <= 1'b0;
        idle_timer    <= 33'd0;
    end else if (!settings_mode) begin
        idle_timer <= 33'd0;
        if (key_enter_exit) begin
            settings_mode <= 1'b1;
            setting_item  <= 3'd0;
        end
    end else begin
        if (key_next_item || key_decrease || key_enter_exit || key_increase)
            idle_timer <= 33'd0;
        else if (idle_timer >= TIMEOUT_CYCLES - 1'b1) begin
            idle_timer    <= 33'd0;
            settings_mode <= 1'b0;
        end else
            idle_timer <= idle_timer + 1'b1;

        if (key_enter_exit)
            settings_mode <= 1'b0;
        else if (key_next_item)
            setting_item <= (setting_item == 3'd7) ? 3'd0 : setting_item + 1'b1;
        else if (key_decrease) begin
            case (setting_item)
                2'd0: if (volume_setting     != 0) volume_setting     <= volume_setting - 1'b1;
                2'd1: if (brightness_setting != 0) brightness_setting <= brightness_setting - 1'b1;
                2'd2: if (contrast_setting   != 0) contrast_setting   <= contrast_setting - 1'b1;
                2'd3: if (sharpness_setting  != 0) sharpness_setting  <= sharpness_setting - 1'b1;
                3'd4: if (saturation_setting != 0) saturation_setting <= saturation_setting - 1'b1;
                3'd5: invert_setting <= 1'b0;
                3'd6: vintage_setting <= 1'b0;
                3'd7: if(enhancement_setting!=0) enhancement_setting<=enhancement_setting-1'b1;
            endcase
        end else if (key_increase) begin
            case (setting_item)
                2'd0: if (volume_setting     < 8) volume_setting     <= volume_setting + 1'b1;
                2'd1: if (brightness_setting < 8) brightness_setting <= brightness_setting + 1'b1;
                2'd2: if (contrast_setting   < 8) contrast_setting   <= contrast_setting + 1'b1;
                2'd3: if (sharpness_setting  < 3) sharpness_setting  <= sharpness_setting + 1'b1;
                3'd4: if (saturation_setting < 8) saturation_setting <= saturation_setting + 1'b1;
                3'd5: invert_setting <= 1'b1;
                3'd6: vintage_setting <= 1'b1;
                3'd7: if(enhancement_setting<2) enhancement_setting<=enhancement_setting+1'b1;
            endcase
        end
    end
end
endmodule

module saixian_audio_volume(
    input  wire [3:0]  volume_setting,
    input  wire [23:0] audio_left_in,
    input  wire [23:0] audio_right_in,
    input  wire [7:0]  level_in,
    output reg  [23:0] audio_left_out,
    output reg  [23:0] audio_right_out,
    output reg  [7:0]  level_out
);
function signed [23:0] scale_sample;
    input signed [23:0] sample;
    input [3:0] level;
    begin
        case (level)
            4'd0: scale_sample = 24'sd0;
            4'd1: scale_sample = sample >>> 4;
            4'd2: scale_sample = sample >>> 3;
            4'd3: scale_sample = sample >>> 2;
            4'd4: scale_sample = sample >>> 1;
            4'd5: scale_sample = (sample >>> 1) + (sample >>> 3);
            4'd6: scale_sample = (sample >>> 1) + (sample >>> 2);
            4'd7: scale_sample = sample - (sample >>> 3);
            default: scale_sample = sample;
        endcase
    end
endfunction
always @* begin
    audio_left_out  = scale_sample($signed(audio_left_in), volume_setting);
    audio_right_out = scale_sample($signed(audio_right_in), volume_setting);
    case (volume_setting)
        4'd0: level_out = 8'd0;
        4'd1: level_out = level_in >> 4;
        4'd2: level_out = level_in >> 3;
        4'd3: level_out = level_in >> 2;
        4'd4: level_out = level_in >> 1;
        4'd5: level_out = (level_in >> 1) + (level_in >> 3);
        4'd6: level_out = (level_in >> 1) + (level_in >> 2);
        4'd7: level_out = level_in - (level_in >> 3);
        default: level_out = level_in;
    endcase
end
endmodule

// Seven-cycle causal 3x3 luminance processor. All taps refer to the current
// raster position or earlier positions: no hidden line/frame delay, no OSD
// pixels in the statistics. Range gating protects strong edges. This is a
// compact edge-aware filter, NOT a full bilateral/Retinex/CLAHE algorithm.
module saixian_adaptive_enhance #(
    parameter integer WIDTH=1280, SPLIT_X=640
)(
    input wire clk,rst,de,vs,frame_tick,statistics_enable,
    input wire [10:0] x,input wire [9:0] y,
    input wire [23:0] rgb_in,input wire [1:0] mode,strength,
    output reg [23:0] rgb_out,
    output wire de_out,vs_out,
    output wire [10:0] x_out,output wire [9:0] y_out,
    output wire [1:0] gain_out
);
wire [9:0] luma_sum={2'd0,rgb_in[23:16]}+{1'b0,rgb_in[15:8],1'b0}+{2'd0,rgb_in[7:0]};
wire [7:0] luma=luma_sum[9:2];
reg [7:0] line1 [0:WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] line2 [0:WIDTH-1]; /* fehdl force_ram=1, ram_style="bram" */
reg [7:0] above,above2;
reg [6:0] de_pipe,vs_pipe;
reg [10:0] xp [0:6];reg [9:0] yp [0:6];
reg [23:0] rgb0,rgb_tap,rgb1,rgb2,rgb3,rgb4;
reg [7:0] y0,y_tap,y1,y2;
reg [8:0] p0_q,p1_q,p2_q,p3_q;
reg [7:0] l0,ll0,l1,ll1,l2,ll2;
reg [11:0] neighborhood;
reg signed [9:0] detail;
reg [15:0] curve_product;
reg signed [8:0] correction;
reg signed [4:0] detail_q;
reg [6:0] tone_q;
reg bypass_q;
reg [1:0] gain;
reg [19:0] stat_sum;
reg [11:0] stat_count;
wire [19:0] stat_count_ext={8'd0,stat_count};
assign gain_out=gain;
assign de_out=de_pipe[6];assign vs_out=vs_pipe[6];
assign x_out=xp[6];assign y_out=yp[6];
function [7:0] tap;
    input [7:0] a,b;input valid;
    reg [7:0] difference;
    begin
        difference=(a>b) ? a-b : b-a;
        tap=(valid && difference<=8'd24) ? b : a;
    end
endfunction
function [7:0] clamp_enhanced;
    input signed [12:0] v;
    begin clamp_enhanced=(v<0) ? 0 : ((v>255) ? 255 : v[7:0]);end
endfunction
wire [7:0] t0=tap(y0,l0,xp[0]>0);
wire [7:0] t1=tap(y0,ll0,xp[0]>1);
wire [7:0] t2=tap(y0,above,yp[0]>0);
wire [7:0] t3=tap(y0,l1,yp[0]>0 && xp[0]>0);
wire [7:0] t4=tap(y0,ll1,yp[0]>0 && xp[0]>1);
wire [7:0] t5=tap(y0,above2,yp[0]>1);
wire [7:0] t6=tap(y0,l2,yp[0]>1 && xp[0]>0);
wire [7:0] t7=tap(y0,ll2,yp[0]>1 && xp[0]>1);
// Balanced partial sums keep eight range decisions off a long adder chain.
wire [8:0] p0={1'b0,t0}+t1,p1={1'b0,t2}+t3,p2={1'b0,t4}+t5,p3={1'b0,t6}+t7;
wire [9:0] pair0={1'b0,p0_q}+p1_q,pair1={1'b0,p2_q}+p3_q;
wire signed [9:0] residual=$signed({1'b0,y1})-$signed({1'b0,neighborhood[11:4]});
reg signed [9:0] detail_term;
reg signed [7:0] tone_term;
always @* begin
    // Preserve low-contrast lettering/texture rather than replacing it with
    // the causal neighborhood average. Keep the existing edge sharpening.
    if(detail>=-3 && detail<=3) detail_term=0;
    else case(strength)
        0:detail_term=0;1:detail_term=detail>>>1;
        2:detail_term=detail;default:detail_term=detail+(detail>>>1);
    endcase
    if(detail_term>12) detail_term=12;
    if(detail_term< -12) detail_term=-12;
    case(gain)
        0:tone_term=0;
        // Half the previous lift: retain more mid-tone contrast/headroom.
        1:tone_term=$signed({2'b0,curve_product[15:10]});
        2:tone_term=$signed({1'b0,curve_product[15:9]});
        default:tone_term=$signed({1'b0,curve_product[15:9]})+$signed({2'b0,curve_product[15:10]});
    endcase
end
integer i;
// RAM has no reset: row/column validity masks exclude old/uninitialised taps.
always @(posedge clk) begin
    if(de && x<WIDTH) begin above<=line1[x];above2<=line2[x];line1[x]<=luma;end
    if(de_pipe[0] && xp[0]<WIDTH) line2[xp[0]]<=above;
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        de_pipe<=0;vs_pipe<=0;rgb0<=0;rgb_tap<=0;rgb1<=0;rgb2<=0;rgb3<=0;rgb4<=0;rgb_out<=0;
        detail_q<=0;tone_q<=0;bypass_q<=0;
        y0<=0;y_tap<=0;y1<=0;y2<=0;p0_q<=0;p1_q<=0;p2_q<=0;p3_q<=0;
        l0<=0;ll0<=0;l1<=0;ll1<=0;l2<=0;ll2<=0;
        neighborhood<=0;detail<=0;curve_product<=0;correction<=0;
        gain<=1;stat_sum<=0;stat_count<=0;
        for(i=0;i<7;i=i+1) begin xp[i]<=0;yp[i]<=0;end
    end else begin
        de_pipe<={de_pipe[5:0],de};vs_pipe<={vs_pipe[5:0],vs};
        xp[0]<=x;yp[0]<=y;
        for(i=1;i<7;i=i+1) begin xp[i]<=xp[i-1];yp[i]<=yp[i-1];end
        rgb0<=rgb_in;y0<=luma;
        rgb_tap<=rgb0;y_tap<=y0;p0_q<=p0;p1_q<=p1;p2_q<=p2;p3_q<=p3;
        rgb1<=rgb_tap;y1<=y_tap;
        if(de_pipe[0]) begin
            if(xp[0]==0) begin ll0<=y0;ll1<=above;ll2<=above2;end
            else begin ll0<=l0;ll1<=l1;ll2<=l2;end
            l0<=y0;l1<=above;l2<=above2;
        end
        neighborhood<=({4'd0,y_tap}<<3)+{2'd0,pair0}+{2'd0,pair1};
        rgb2<=rgb1;y2<=y1;detail<=residual;
        curve_product<=y1*(8'd255-y1);
        rgb3<=rgb2;
        detail_q<=detail_term[4:0];tone_q<=tone_term[6:0];
        bypass_q<=((mode==0) || (mode==2 && xp[3]<SPLIT_X));
        rgb4<=rgb3;
        correction<=bypass_q ? 9'sd0 : $signed({2'b0,tone_q})+$signed({{4{detail_q[4]}},detail_q});
        rgb_out<=de_pipe[5] ? {clamp_enhanced($signed({1'b0,rgb4[23:16]})+correction),
                               clamp_enhanced($signed({1'b0,rgb4[15:8]})+correction),
                               clamp_enhanced($signed({1'b0,rgb4[7:0]})+correction)} : 24'd0;
        // 1/256 spatial sampling; no per-pixel divider or histogram storage.
        if(frame_tick) begin
            if(stat_count>32) begin
                if(stat_sum<(stat_count_ext<<6)) gain<=3;
                else if(stat_sum<((stat_count_ext<<6)+(stat_count_ext<<5))) gain<=2;
                else if(stat_sum<((stat_count_ext<<7)+(stat_count_ext<<4))) gain<=1;
                else gain<=0;
            end
            stat_sum<=0;stat_count<=0;
        end else if(de && statistics_enable && x[3:0]==0 && y[3:0]==0) begin
            stat_sum<=stat_sum+luma;stat_count<=stat_count+1'b1;
        end
    end
end
endmodule

module saixian_picture_adjust_pipe(
    input wire clk, input wire rst, input wire de, input wire [10:0] x,
    input wire [23:0] rgb_in,
    input wire [3:0] brightness_setting, input wire [3:0] contrast_setting,
    input wire [3:0] saturation_setting, input wire [1:0] sharpness_setting,
    output reg [23:0] rgb_out
);
reg [23:0] previous_rgb;
reg [23:0] rgb_in_s0;
reg        de_s0;
reg [10:0] x_s0;
// Conservative full-control ranges: contrast/brightness [-607,863],
// saturation [-447,701]. Eleven signed bits retain exact integer results.
reg signed [10:0] red_work_s1, green_work_s1, blue_work_s1;
reg [7:0] red_pre_s2, green_pre_s2, blue_pre_s2;
reg signed [8:0] luma_s2;
reg signed [10:0] red_work_comb, green_work_comb, blue_work_comb;
reg signed [11:0] red_delta_comb, green_delta_comb, blue_delta_comb;
reg signed [11:0] red_delta_s1, green_delta_s1, blue_delta_s1;
reg [7:0] red_base_s1, green_base_s1, blue_base_s1;
reg signed [10:0] brightness_offset_comb;
reg signed [10:0] brightness_offset_s1;
reg [10:0] contrast_config_s1, saturation_config_s2;
// Separate subtract, DSP multiply, Q4 rounding/add and clamp. Total latency: 8 clocks.
reg signed [8:0] red_sat_delta_s3, green_sat_delta_s3, blue_sat_delta_s3;
reg [10:0] saturation_config_s3;
reg signed [8:0] luma_s3, luma_s4;
reg signed [14:0] red_product_s4, green_product_s4, blue_product_s4;
reg [3:0] saturation_bias_s4;
reg red_carry_s4, green_carry_s4, blue_carry_s4;
reg signed [10:0] red_sat_s5, green_sat_s5, blue_sat_s5;

function gain_carry;
    input signed [8:0] value; input [1:0] selector;
    begin
        gain_carry=selector==1 ? value[2]&value[0] :
                   selector==2 ? value[1]&value[0] : 1'b0;
    end
endfunction

function signed [10:0] finish_saturation;
    input signed [14:0] product; input [3:0] bias;
    input carry_bit; input signed [8:0] luma_value;
    reg signed [14:0] rounded;
    begin
        rounded=product+$signed({1'b0,bias});
        finish_saturation=luma_value+(rounded>>>4)-$signed({1'b0,carry_bit});
    end
endfunction

// Decode frame-stable controls before the pixel multiplier path. Bits are
// {positive Q4 coefficient, rounding bias, low-bit correction selector}.
function [10:0] gain_config;
    input [3:0] level;input saturation;
    reg [4:0] coefficient;reg [3:0] bias;reg [1:0] carry_select;
    begin
        bias=0;carry_select=0;
        if(saturation) begin
            case(level)
                0:coefficient=0;1:coefficient=4;2:coefficient=8;
                3:begin coefficient=12;bias=12;end
                4:coefficient=16;5:coefficient=18;6:coefficient=20;7:coefficient=24;
                default:begin coefficient=28;carry_select=2;end
            endcase
        end else begin
            case(level)
                0:coefficient=8;1:begin coefficient=10;carry_select=1;end
                2:begin coefficient=12;carry_select=2;end
                3:begin coefficient=14;bias=14;end
                4:coefficient=16;5:coefficient=18;6:coefficient=20;7:coefficient=24;
                default:begin coefficient=28;carry_select=2;end
            endcase
        end
        gain_config={coefficient,bias,carry_select};
    end
endfunction
function signed [10:0] decoded_gain;
    input signed [10:0] value;input [10:0] config_bits;
    reg signed [16:0] product;reg carry_bit;
    begin
        product=value*$signed({1'b0,config_bits[10:6]});
        carry_bit=config_bits[1:0]==1 ? value[2]&value[0] :
                  config_bits[1:0]==2 ? value[1]&value[0] : 1'b0;
        decoded_gain=((product+$signed({1'b0,config_bits[5:2]}))>>>4)-$signed({1'b0,carry_bit});
    end
endfunction

function signed [10:0] contrast_scale_pipe;
    input signed [10:0] value; input [3:0] level;
    reg [4:0] coefficient;
    reg [3:0] rounding_bias;
    reg correction_bit;
    reg signed [16:0] product;
    begin
        rounding_bias=0;correction_bit=0;
        case(level)
            0:coefficient=8;
            1:begin coefficient=10;correction_bit=value[2]&value[0];end
            2:begin coefficient=12;correction_bit=value[1]&value[0];end
            3:begin coefficient=14;rounding_bias=14;end
            4:coefficient=16;5:coefficient=18;
            6:coefficient=20;7:coefficient=24;
            default:begin coefficient=28;correction_bit=value[1]&value[0];end
        endcase
        product=value*$signed({1'b0,coefficient});
        // Bias/carry correction preserves the old separate arithmetic-shift
        // rounding exactly, including negative inputs (not approximate gain).
        contrast_scale_pipe=((product+$signed({1'b0,rounding_bias}))>>>4)-$signed({1'b0,correction_bit});
    end
endfunction
function signed [10:0] saturation_scale_pipe;
    input signed [10:0] value; input [3:0] level;
    reg [4:0] coefficient;
    reg [3:0] rounding_bias;
    reg correction_bit;
    reg signed [16:0] product;
    begin
        rounding_bias=0;correction_bit=0;
        case(level)
            0:coefficient=0;1:coefficient=4;2:coefficient=8;
            3:begin coefficient=12;rounding_bias=12;end
            4:coefficient=16;5:coefficient=18;
            6:coefficient=20;7:coefficient=24;
            default:begin coefficient=28;correction_bit=value[1]&value[0];end
        endcase
        product=value*$signed({1'b0,coefficient});
        saturation_scale_pipe=((product+$signed({1'b0,rounding_bias}))>>>4)-$signed({1'b0,correction_bit});
    end
endfunction
function [7:0] clamp_pipe;
    input signed [10:0] value;
    begin
        if(value[10]) clamp_pipe=8'd0;
        else if(|value[9:8]) clamp_pipe=8'd255;
        else clamp_pipe=value[7:0];
    end
endfunction

wire [7:0] red_pre_wire=clamp_pipe(red_work_s1);
wire [7:0] green_pre_wire=clamp_pipe(green_work_s1);
wire [7:0] blue_pre_wire=clamp_pipe(blue_work_s1);
wire signed [10:0] luma_wire=($signed({1'b0,red_pre_wire})+
    ($signed({1'b0,green_pre_wire})<<<1)+$signed({1'b0,blue_pre_wire}))>>>2;

always @* begin
    case(brightness_setting)
        0:brightness_offset_comb=-11'sd64; 1:brightness_offset_comb=-11'sd48;
        2:brightness_offset_comb=-11'sd32; 3:brightness_offset_comb=-11'sd16;
        4:brightness_offset_comb=11'sd0; 5:brightness_offset_comb=11'sd16;
        6:brightness_offset_comb=11'sd32; 7:brightness_offset_comb=11'sd48;
        default:brightness_offset_comb=11'sd64;
    endcase
    red_delta_comb=$signed({1'b0,rgb_in_s0[23:16]})-$signed({1'b0,previous_rgb[23:16]});
    green_delta_comb=$signed({1'b0,rgb_in_s0[15:8]})-$signed({1'b0,previous_rgb[15:8]});
    blue_delta_comb=$signed({1'b0,rgb_in_s0[7:0]})-$signed({1'b0,previous_rgb[7:0]});
    if(!de_s0||(x_s0==0)) begin red_delta_comb=0; green_delta_comb=0; blue_delta_comb=0; end
    case(sharpness_setting)
        0:begin red_delta_comb=0;green_delta_comb=0;blue_delta_comb=0;end
        1:begin red_delta_comb=red_delta_comb>>>2;green_delta_comb=green_delta_comb>>>2;blue_delta_comb=blue_delta_comb>>>2;end
        2:begin red_delta_comb=red_delta_comb>>>1;green_delta_comb=green_delta_comb>>>1;blue_delta_comb=blue_delta_comb>>>1;end
        default:;
    endcase
    red_work_comb=decoded_gain($signed({1'b0,red_base_s1})+red_delta_s1-13'sd128,contrast_config_s1)+13'sd128+brightness_offset_s1;
    green_work_comb=decoded_gain($signed({1'b0,green_base_s1})+green_delta_s1-13'sd128,contrast_config_s1)+13'sd128+brightness_offset_s1;
    blue_work_comb=decoded_gain($signed({1'b0,blue_base_s1})+blue_delta_s1-13'sd128,contrast_config_s1)+13'sd128+brightness_offset_s1;
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        previous_rgb<=0; rgb_in_s0<=0; de_s0<=0; x_s0<=0;
        red_delta_s1<=0; green_delta_s1<=0; blue_delta_s1<=0;
        red_base_s1<=0; green_base_s1<=0; blue_base_s1<=0;
        brightness_offset_s1<=0;contrast_config_s1<=gain_config(4'd4,1'b0);
        saturation_config_s2<=gain_config(4'd4,1'b1);
        red_work_s1<=0; green_work_s1<=0; blue_work_s1<=0;
        red_pre_s2<=0; green_pre_s2<=0; blue_pre_s2<=0; luma_s2<=0; rgb_out<=0;
        red_sat_delta_s3<=0; green_sat_delta_s3<=0; blue_sat_delta_s3<=0;
        saturation_config_s3<=gain_config(4'd4,1'b1); luma_s3<=0; luma_s4<=0;
        red_product_s4<=0; green_product_s4<=0; blue_product_s4<=0;
        saturation_bias_s4<=0; red_carry_s4<=0; green_carry_s4<=0; blue_carry_s4<=0;
        red_sat_s5<=0; green_sat_s5<=0; blue_sat_s5<=0;
    end else begin
        rgb_in_s0<=rgb_in; de_s0<=de; x_s0<=x;
        brightness_offset_s1<=brightness_offset_comb;
        contrast_config_s1<=gain_config(contrast_setting,1'b0);
        saturation_config_s2<=gain_config(saturation_setting,1'b1);
        if(de_s0) previous_rgb<=rgb_in_s0;
        red_delta_s1<=red_delta_comb; green_delta_s1<=green_delta_comb; blue_delta_s1<=blue_delta_comb;
        red_base_s1<=rgb_in_s0[23:16]; green_base_s1<=rgb_in_s0[15:8]; blue_base_s1<=rgb_in_s0[7:0];
        red_work_s1<=red_work_comb; green_work_s1<=green_work_comb; blue_work_s1<=blue_work_comb;
        red_pre_s2<=red_pre_wire; green_pre_s2<=green_pre_wire; blue_pre_s2<=blue_pre_wire; luma_s2<=luma_wire;
        red_sat_delta_s3<=$signed({1'b0,red_pre_s2})-luma_s2;
        green_sat_delta_s3<=$signed({1'b0,green_pre_s2})-luma_s2;
        blue_sat_delta_s3<=$signed({1'b0,blue_pre_s2})-luma_s2;
        luma_s3<=luma_s2; saturation_config_s3<=saturation_config_s2;
        red_product_s4<=red_sat_delta_s3*$signed({1'b0,saturation_config_s3[10:6]});
        green_product_s4<=green_sat_delta_s3*$signed({1'b0,saturation_config_s3[10:6]});
        blue_product_s4<=blue_sat_delta_s3*$signed({1'b0,saturation_config_s3[10:6]});
        luma_s4<=luma_s3; saturation_bias_s4<=saturation_config_s3[5:2];
        red_carry_s4<=gain_carry(red_sat_delta_s3,saturation_config_s3[1:0]);
        green_carry_s4<=gain_carry(green_sat_delta_s3,saturation_config_s3[1:0]);
        blue_carry_s4<=gain_carry(blue_sat_delta_s3,saturation_config_s3[1:0]);
        red_sat_s5<=finish_saturation(red_product_s4,saturation_bias_s4,red_carry_s4,luma_s4);
        green_sat_s5<=finish_saturation(green_product_s4,saturation_bias_s4,green_carry_s4,luma_s4);
        blue_sat_s5<=finish_saturation(blue_product_s4,saturation_bias_s4,blue_carry_s4,luma_s4);
        rgb_out<={clamp_pipe(red_sat_s5),clamp_pipe(green_sat_s5),clamp_pipe(blue_sat_s5)};
    end
end
endmodule
module saixian_picture_adjust(
    input  wire        clk,
    input  wire        rst,
    input  wire        de,
    input  wire [9:0]  x,
    input  wire [23:0] rgb_in,
    input  wire [3:0]  brightness_setting,
    input  wire [3:0]  contrast_setting,
    input  wire [3:0]  saturation_setting,
    input  wire [1:0]  sharpness_setting,
    output reg  [23:0] rgb_out
);
reg [23:0] previous_rgb;
reg signed [12:0] red_work, green_work, blue_work;
reg signed [11:0] red_delta, green_delta, blue_delta;
reg signed [10:0] brightness_offset;
reg [7:0] red_pre, green_pre, blue_pre;
reg signed [12:0] luma_work;
reg signed [12:0] red_sat, green_sat, blue_sat;

function signed [12:0] contrast_scale;
    input signed [12:0] value;
    input [3:0] level;
    begin
        case (level)
            4'd0: contrast_scale = value >>> 1;
            4'd1: contrast_scale = (value >>> 1) + (value >>> 3);
            4'd2: contrast_scale = (value >>> 1) + (value >>> 2);
            4'd3: contrast_scale = value - (value >>> 3);
            4'd4: contrast_scale = value;
            4'd5: contrast_scale = value + (value >>> 3);
            4'd6: contrast_scale = value + (value >>> 2);
            4'd7: contrast_scale = value + (value >>> 1);
            default: contrast_scale = value + (value >>> 1) + (value >>> 2);
        endcase
    end
endfunction

function signed [12:0] saturation_scale;
    input signed [12:0] value;
    input [3:0] level;
    begin
        case (level)
            4'd0: saturation_scale = 13'sd0;
            4'd1: saturation_scale = value >>> 2;
            4'd2: saturation_scale = value >>> 1;
            4'd3: saturation_scale = value - (value >>> 2);
            4'd4: saturation_scale = value;
            4'd5: saturation_scale = value + (value >>> 3);
            4'd6: saturation_scale = value + (value >>> 2);
            4'd7: saturation_scale = value + (value >>> 1);
            default: saturation_scale = value + (value >>> 1) + (value >>> 2);
        endcase
    end
endfunction

function [7:0] clamp_channel;
    input signed [12:0] value;
    begin
        if (value < 0)
            clamp_channel = 8'd0;
        else if (value > 13'sd255)
            clamp_channel = 8'd255;
        else
            clamp_channel = value[7:0];
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst)
        previous_rgb <= 24'd0;
    else if (de)
        previous_rgb <= rgb_in;
end

always @* begin
    case (brightness_setting)
        4'd0: brightness_offset = -11'sd64;
        4'd1: brightness_offset = -11'sd48;
        4'd2: brightness_offset = -11'sd32;
        4'd3: brightness_offset = -11'sd16;
        4'd4: brightness_offset =  11'sd0;
        4'd5: brightness_offset =  11'sd16;
        4'd6: brightness_offset =  11'sd32;
        4'd7: brightness_offset =  11'sd48;
        default: brightness_offset = 11'sd64;
    endcase

    red_delta   = $signed({1'b0,rgb_in[23:16]}) - $signed({1'b0,previous_rgb[23:16]});
    green_delta = $signed({1'b0,rgb_in[15:8]})  - $signed({1'b0,previous_rgb[15:8]});
    blue_delta  = $signed({1'b0,rgb_in[7:0]})   - $signed({1'b0,previous_rgb[7:0]});
    if (!de || (x == 0)) begin
        red_delta = 0; green_delta = 0; blue_delta = 0;
    end

    case (sharpness_setting)
        2'd0: begin red_delta = 0; green_delta = 0; blue_delta = 0; end
        2'd1: begin red_delta = red_delta >>> 2; green_delta = green_delta >>> 2; blue_delta = blue_delta >>> 2; end
        2'd2: begin red_delta = red_delta >>> 1; green_delta = green_delta >>> 1; blue_delta = blue_delta >>> 1; end
        default: ;
    endcase

    red_work   = contrast_scale($signed({1'b0,rgb_in[23:16]}) + red_delta - 13'sd128, contrast_setting)
                 + 13'sd128 + brightness_offset;
    green_work = contrast_scale($signed({1'b0,rgb_in[15:8]}) + green_delta - 13'sd128, contrast_setting)
                 + 13'sd128 + brightness_offset;
    blue_work  = contrast_scale($signed({1'b0,rgb_in[7:0]}) + blue_delta - 13'sd128, contrast_setting)
                 + 13'sd128 + brightness_offset;
    red_pre   = clamp_channel(red_work);
    green_pre = clamp_channel(green_work);
    blue_pre  = clamp_channel(blue_work);
    luma_work = ($signed({1'b0,red_pre}) + ($signed({1'b0,green_pre}) <<< 1)
                 + $signed({1'b0,blue_pre})) >>> 2;
    red_sat   = luma_work + saturation_scale($signed({1'b0,red_pre}) - luma_work, saturation_setting);
    green_sat = luma_work + saturation_scale($signed({1'b0,green_pre}) - luma_work, saturation_setting);
    blue_sat  = luma_work + saturation_scale($signed({1'b0,blue_pre}) - luma_work, saturation_setting);
    rgb_out = {clamp_channel(red_sat),clamp_channel(green_sat),clamp_channel(blue_sat)};
end
endmodule

// Image-only HMI filters. Keep OSD and blue-victory scene legible/unmodified.
// Vintage is a low-cost warm monochrome approximation; invert is applied last.
module saixian_hmi_color_style(
    input wire [23:0] rgb_in,
    input wire invert, vintage,
    output wire [23:0] rgb_out
);
wire [9:0] luma_sum={2'b0,rgb_in[23:16]}+
                    {1'b0,rgb_in[15:8],1'b0}+{2'b0,rgb_in[7:0]};
wire [7:0] luma=luma_sum[9:2];
wire [7:0] warm_r=(luma>8'd223) ? 8'd255 : luma+8'd32;
wire [7:0] warm_b=luma-(luma>>2);
wire [23:0] warm=vintage ? {warm_r,luma,warm_b} : rgb_in;
assign rgb_out=invert ? ~warm : warm;
endmodule

// TJC command stream: b[component ID].txt="<value>" followed by FF FF FF.
// The active home page uses IDs 7 (picture), 9 (music), and 11 (error).
// TJC8048X570: page-qualified ASCII commands, each terminated by FF FF FF.
// Referenced HMI components must have vscope=global to survive page races.
module saixian_hmi_status_tx #(
    parameter integer CLK_FREQ_HZ = 75_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input wire clk, rst,
    input wire [2:0] image_count,
    input wire [2:0] audio_count,
    input wire [2:0] error_code,
    input wire initializing,
    input wire [2:0] page_id,
    input wire refresh_request,
    input wire [1:0] sharpness,
    input wire [3:0] brightness, contrast, saturation, volume,
    input wire invert, vintage,
    input wire [3:0] event_state,
    input wire [6:0] minutes,
    input wire [5:0] seconds,
    output reg uart_tx,
    output reg command_sent_pulse
);
localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
localparam [1:0] TX_IDLE=0, TX_START=1, TX_DATA=2, TX_STOP=3;
reg [1:0] tx_state;
reg [4:0] next_field;
reg [2:0] active_page;
reg [31:0] refresh_count;
reg [15:0] baud_count;
reg [4:0] message_id, prepared_id;
reg [7:0] command_rom [0:1023];
reg [7:0] prefix_byte;
integer rom_index;
reg [47:0] message_suffix, prepared_suffix;
reg [5:0] prefix_length, suffix_length;
reg [5:0] message_len, prepared_len, byte_index;
wire [4:0] next_byte_index=byte_index[4:0]+5'd1;
reg [2:0] bit_index;
reg [7:0] shift_byte;
reg [6:0] minutes_snapshot;
reg [5:0] seconds_snapshot;
reg [3:0] state_snapshot;
reg [4:0] field_count;
reg refresh_pending;
reg [19:0] settings_seen;
wire [19:0] settings_live={sharpness,brightness,contrast,saturation,volume,invert,vintage};
reg [7:0] value;
integer prefix_len;

// Fixed ASCII prefixes use one synchronous block ROM instead of wide muxes.
initial begin
    for(rom_index=0;rom_index<1024;rom_index=rom_index+1) command_rom[rom_index]=8'h00;
    command_rom[0]=8'h73;
    command_rom[1]=8'h65;
    command_rom[2]=8'h74;
    command_rom[3]=8'h74;
    command_rom[4]=8'h69;
    command_rom[5]=8'h6e;
    command_rom[6]=8'h67;
    command_rom[7]=8'h73;
    command_rom[8]=8'h2e;
    command_rom[9]=8'h68;
    command_rom[10]=8'h5f;
    command_rom[11]=8'h73;
    command_rom[12]=8'h68;
    command_rom[13]=8'h61;
    command_rom[14]=8'h72;
    command_rom[15]=8'h70;
    command_rom[16]=8'h2e;
    command_rom[17]=8'h76;
    command_rom[18]=8'h61;
    command_rom[19]=8'h6c;
    command_rom[20]=8'h3d;
    command_rom[32]=8'h73;
    command_rom[33]=8'h65;
    command_rom[34]=8'h74;
    command_rom[35]=8'h74;
    command_rom[36]=8'h69;
    command_rom[37]=8'h6e;
    command_rom[38]=8'h67;
    command_rom[39]=8'h73;
    command_rom[40]=8'h2e;
    command_rom[41]=8'h6e;
    command_rom[42]=8'h5f;
    command_rom[43]=8'h73;
    command_rom[44]=8'h68;
    command_rom[45]=8'h61;
    command_rom[46]=8'h72;
    command_rom[47]=8'h70;
    command_rom[48]=8'h2e;
    command_rom[49]=8'h76;
    command_rom[50]=8'h61;
    command_rom[51]=8'h6c;
    command_rom[52]=8'h3d;
    command_rom[64]=8'h73;
    command_rom[65]=8'h65;
    command_rom[66]=8'h74;
    command_rom[67]=8'h74;
    command_rom[68]=8'h69;
    command_rom[69]=8'h6e;
    command_rom[70]=8'h67;
    command_rom[71]=8'h73;
    command_rom[72]=8'h2e;
    command_rom[73]=8'h68;
    command_rom[74]=8'h5f;
    command_rom[75]=8'h62;
    command_rom[76]=8'h72;
    command_rom[77]=8'h69;
    command_rom[78]=8'h67;
    command_rom[79]=8'h68;
    command_rom[80]=8'h74;
    command_rom[81]=8'h2e;
    command_rom[82]=8'h76;
    command_rom[83]=8'h61;
    command_rom[84]=8'h6c;
    command_rom[85]=8'h3d;
    command_rom[96]=8'h73;
    command_rom[97]=8'h65;
    command_rom[98]=8'h74;
    command_rom[99]=8'h74;
    command_rom[100]=8'h69;
    command_rom[101]=8'h6e;
    command_rom[102]=8'h67;
    command_rom[103]=8'h73;
    command_rom[104]=8'h2e;
    command_rom[105]=8'h6e;
    command_rom[106]=8'h5f;
    command_rom[107]=8'h62;
    command_rom[108]=8'h72;
    command_rom[109]=8'h69;
    command_rom[110]=8'h67;
    command_rom[111]=8'h68;
    command_rom[112]=8'h74;
    command_rom[113]=8'h2e;
    command_rom[114]=8'h76;
    command_rom[115]=8'h61;
    command_rom[116]=8'h6c;
    command_rom[117]=8'h3d;
    command_rom[128]=8'h73;
    command_rom[129]=8'h65;
    command_rom[130]=8'h74;
    command_rom[131]=8'h74;
    command_rom[132]=8'h69;
    command_rom[133]=8'h6e;
    command_rom[134]=8'h67;
    command_rom[135]=8'h73;
    command_rom[136]=8'h2e;
    command_rom[137]=8'h68;
    command_rom[138]=8'h5f;
    command_rom[139]=8'h63;
    command_rom[140]=8'h6f;
    command_rom[141]=8'h6e;
    command_rom[142]=8'h74;
    command_rom[143]=8'h72;
    command_rom[144]=8'h61;
    command_rom[145]=8'h73;
    command_rom[146]=8'h74;
    command_rom[147]=8'h2e;
    command_rom[148]=8'h76;
    command_rom[149]=8'h61;
    command_rom[150]=8'h6c;
    command_rom[151]=8'h3d;
    command_rom[160]=8'h73;
    command_rom[161]=8'h65;
    command_rom[162]=8'h74;
    command_rom[163]=8'h74;
    command_rom[164]=8'h69;
    command_rom[165]=8'h6e;
    command_rom[166]=8'h67;
    command_rom[167]=8'h73;
    command_rom[168]=8'h2e;
    command_rom[169]=8'h6e;
    command_rom[170]=8'h5f;
    command_rom[171]=8'h63;
    command_rom[172]=8'h6f;
    command_rom[173]=8'h6e;
    command_rom[174]=8'h74;
    command_rom[175]=8'h72;
    command_rom[176]=8'h61;
    command_rom[177]=8'h73;
    command_rom[178]=8'h74;
    command_rom[179]=8'h2e;
    command_rom[180]=8'h76;
    command_rom[181]=8'h61;
    command_rom[182]=8'h6c;
    command_rom[183]=8'h3d;
    command_rom[192]=8'h73;
    command_rom[193]=8'h65;
    command_rom[194]=8'h74;
    command_rom[195]=8'h74;
    command_rom[196]=8'h69;
    command_rom[197]=8'h6e;
    command_rom[198]=8'h67;
    command_rom[199]=8'h73;
    command_rom[200]=8'h2e;
    command_rom[201]=8'h68;
    command_rom[202]=8'h5f;
    command_rom[203]=8'h73;
    command_rom[204]=8'h61;
    command_rom[205]=8'h74;
    command_rom[206]=8'h75;
    command_rom[207]=8'h72;
    command_rom[208]=8'h61;
    command_rom[209]=8'h74;
    command_rom[210]=8'h69;
    command_rom[211]=8'h6f;
    command_rom[212]=8'h6e;
    command_rom[213]=8'h2e;
    command_rom[214]=8'h76;
    command_rom[215]=8'h61;
    command_rom[216]=8'h6c;
    command_rom[217]=8'h3d;
    command_rom[224]=8'h73;
    command_rom[225]=8'h65;
    command_rom[226]=8'h74;
    command_rom[227]=8'h74;
    command_rom[228]=8'h69;
    command_rom[229]=8'h6e;
    command_rom[230]=8'h67;
    command_rom[231]=8'h73;
    command_rom[232]=8'h2e;
    command_rom[233]=8'h6e;
    command_rom[234]=8'h5f;
    command_rom[235]=8'h73;
    command_rom[236]=8'h61;
    command_rom[237]=8'h74;
    command_rom[238]=8'h75;
    command_rom[239]=8'h72;
    command_rom[240]=8'h61;
    command_rom[241]=8'h74;
    command_rom[242]=8'h69;
    command_rom[243]=8'h6f;
    command_rom[244]=8'h6e;
    command_rom[245]=8'h2e;
    command_rom[246]=8'h76;
    command_rom[247]=8'h61;
    command_rom[248]=8'h6c;
    command_rom[249]=8'h3d;
    command_rom[256]=8'h73;
    command_rom[257]=8'h65;
    command_rom[258]=8'h74;
    command_rom[259]=8'h74;
    command_rom[260]=8'h69;
    command_rom[261]=8'h6e;
    command_rom[262]=8'h67;
    command_rom[263]=8'h73;
    command_rom[264]=8'h2e;
    command_rom[265]=8'h68;
    command_rom[266]=8'h5f;
    command_rom[267]=8'h76;
    command_rom[268]=8'h6f;
    command_rom[269]=8'h6c;
    command_rom[270]=8'h75;
    command_rom[271]=8'h6d;
    command_rom[272]=8'h65;
    command_rom[273]=8'h2e;
    command_rom[274]=8'h76;
    command_rom[275]=8'h61;
    command_rom[276]=8'h6c;
    command_rom[277]=8'h3d;
    command_rom[288]=8'h73;
    command_rom[289]=8'h65;
    command_rom[290]=8'h74;
    command_rom[291]=8'h74;
    command_rom[292]=8'h69;
    command_rom[293]=8'h6e;
    command_rom[294]=8'h67;
    command_rom[295]=8'h73;
    command_rom[296]=8'h2e;
    command_rom[297]=8'h6e;
    command_rom[298]=8'h5f;
    command_rom[299]=8'h76;
    command_rom[300]=8'h6f;
    command_rom[301]=8'h6c;
    command_rom[302]=8'h75;
    command_rom[303]=8'h6d;
    command_rom[304]=8'h65;
    command_rom[305]=8'h2e;
    command_rom[306]=8'h76;
    command_rom[307]=8'h61;
    command_rom[308]=8'h6c;
    command_rom[309]=8'h3d;
    command_rom[320]=8'h73;
    command_rom[321]=8'h65;
    command_rom[322]=8'h74;
    command_rom[323]=8'h74;
    command_rom[324]=8'h69;
    command_rom[325]=8'h6e;
    command_rom[326]=8'h67;
    command_rom[327]=8'h73;
    command_rom[328]=8'h2e;
    command_rom[329]=8'h62;
    command_rom[330]=8'h74;
    command_rom[331]=8'h5f;
    command_rom[332]=8'h69;
    command_rom[333]=8'h6e;
    command_rom[334]=8'h76;
    command_rom[335]=8'h65;
    command_rom[336]=8'h72;
    command_rom[337]=8'h74;
    command_rom[338]=8'h2e;
    command_rom[339]=8'h76;
    command_rom[340]=8'h61;
    command_rom[341]=8'h6c;
    command_rom[342]=8'h3d;
    command_rom[352]=8'h73;
    command_rom[353]=8'h65;
    command_rom[354]=8'h74;
    command_rom[355]=8'h74;
    command_rom[356]=8'h69;
    command_rom[357]=8'h6e;
    command_rom[358]=8'h67;
    command_rom[359]=8'h73;
    command_rom[360]=8'h2e;
    command_rom[361]=8'h62;
    command_rom[362]=8'h74;
    command_rom[363]=8'h5f;
    command_rom[364]=8'h76;
    command_rom[365]=8'h69;
    command_rom[366]=8'h6e;
    command_rom[367]=8'h74;
    command_rom[368]=8'h61;
    command_rom[369]=8'h67;
    command_rom[370]=8'h65;
    command_rom[371]=8'h2e;
    command_rom[372]=8'h76;
    command_rom[373]=8'h61;
    command_rom[374]=8'h6c;
    command_rom[375]=8'h3d;
    command_rom[384]=8'h67;
    command_rom[385]=8'h61;
    command_rom[386]=8'h6d;
    command_rom[387]=8'h65;
    command_rom[388]=8'h2e;
    command_rom[389]=8'h74;
    command_rom[390]=8'h34;
    command_rom[391]=8'h2e;
    command_rom[392]=8'h74;
    command_rom[393]=8'h78;
    command_rom[394]=8'h74;
    command_rom[395]=8'h3d;
    command_rom[396]=8'h22;
    command_rom[416]=8'h67;
    command_rom[417]=8'h61;
    command_rom[418]=8'h6d;
    command_rom[419]=8'h65;
    command_rom[420]=8'h2e;
    command_rom[421]=8'h74;
    command_rom[422]=8'h33;
    command_rom[423]=8'h2e;
    command_rom[424]=8'h74;
    command_rom[425]=8'h78;
    command_rom[426]=8'h74;
    command_rom[427]=8'h3d;
    command_rom[428]=8'h22;
    command_rom[448]=8'h67;
    command_rom[449]=8'h61;
    command_rom[450]=8'h6d;
    command_rom[451]=8'h65;
    command_rom[452]=8'h2e;
    command_rom[453]=8'h6e;
    command_rom[454]=8'h5f;
    command_rom[455]=8'h73;
    command_rom[456]=8'h74;
    command_rom[457]=8'h61;
    command_rom[458]=8'h74;
    command_rom[459]=8'h65;
    command_rom[460]=8'h2e;
    command_rom[461]=8'h76;
    command_rom[462]=8'h61;
    command_rom[463]=8'h6c;
    command_rom[464]=8'h3d;
    command_rom[480]=8'h68;
    command_rom[481]=8'h6f;
    command_rom[482]=8'h6d;
    command_rom[483]=8'h65;
    command_rom[484]=8'h2e;
    command_rom[485]=8'h74;
    command_rom[486]=8'h5f;
    command_rom[487]=8'h70;
    command_rom[488]=8'h2e;
    command_rom[489]=8'h74;
    command_rom[490]=8'h78;
    command_rom[491]=8'h74;
    command_rom[492]=8'h3d;
    command_rom[493]=8'h22;
    command_rom[512]=8'h68;
    command_rom[513]=8'h6f;
    command_rom[514]=8'h6d;
    command_rom[515]=8'h65;
    command_rom[516]=8'h2e;
    command_rom[517]=8'h74;
    command_rom[518]=8'h5f;
    command_rom[519]=8'h6d;
    command_rom[520]=8'h2e;
    command_rom[521]=8'h74;
    command_rom[522]=8'h78;
    command_rom[523]=8'h74;
    command_rom[524]=8'h3d;
    command_rom[525]=8'h22;
    command_rom[544]=8'h68;
    command_rom[545]=8'h6f;
    command_rom[546]=8'h6d;
    command_rom[547]=8'h65;
    command_rom[548]=8'h2e;
    command_rom[549]=8'h74;
    command_rom[550]=8'h5f;
    command_rom[551]=8'h65;
    command_rom[552]=8'h2e;
    command_rom[553]=8'h74;
    command_rom[554]=8'h78;
    command_rom[555]=8'h74;
    command_rom[556]=8'h3d;
    command_rom[557]=8'h22;
end
always @(posedge clk) prefix_byte<=command_rom[{message_id,next_byte_index}];

// Reverse mapping chooses a stable representative of the FPGA's 0..8 levels.
function [7:0] percent;
    input [3:0] level;
    begin
        case(level)
            0:percent=0; 1:percent=13; 2:percent=25; 3:percent=38;
            4:percent=50; 5:percent=63; 6:percent=75; 7:percent=88;
            default:percent=100;
        endcase
    end
endfunction

// Format a constant prefix and short numeric suffix separately.
// Numeric settings always use three decimal digits (000..100).
always @* begin
    prepared_suffix=0; prepared_len=0; prepared_id=0; prefix_len=0; value=0;
    field_count=3;
    case(active_page)
        3'd1: begin
            field_count=12;
            case(next_field)
                0:begin prepared_id=5'd0;prefix_len=21;value={6'd0,sharpness};end
                1:begin prepared_id=5'd1;prefix_len=21;value={6'd0,sharpness};end
                2:begin prepared_id=5'd2;prefix_len=22;value=percent(brightness);end
                3:begin prepared_id=5'd3;prefix_len=22;value=percent(brightness);end
                4:begin prepared_id=5'd4;prefix_len=24;value=percent(contrast);end
                5:begin prepared_id=5'd5;prefix_len=24;value=percent(contrast);end
                6:begin prepared_id=5'd6;prefix_len=26;value=percent(saturation);end
                7:begin prepared_id=5'd7;prefix_len=26;value=percent(saturation);end
                8:begin prepared_id=5'd8;prefix_len=22;value=percent(volume);end
                9:begin prepared_id=5'd9;prefix_len=22;value=percent(volume);end
                10:begin prepared_id=5'd10;prefix_len=23;value={7'd0,invert};end
                default:begin prepared_id=5'd11;prefix_len=24;value={7'd0,vintage};end
            endcase
        end
        3'd2: begin
            field_count=3;
            case(next_field)
                0:begin prepared_id=5'd12;prefix_len=13;end
                1:begin prepared_id=5'd13;prefix_len=13;end
                default:begin prepared_id=5'd14;prefix_len=17;value={4'd0,state_snapshot};end
            endcase
        end
        3'd0: begin
            case(next_field)
                0:begin prepared_id=5'd15;prefix_len=14;end
                1:begin prepared_id=5'd16;prefix_len=14;end
                default:begin prepared_id=5'd17;prefix_len=14;end
            endcase
        end
        default:field_count=0; // settlement/keyboard pages have no telemetry targets
    endcase
    prepared_len=prefix_len;
    if(active_page==1 || (active_page==2 && next_field==2)) begin
        prepared_suffix={8'h30+value/8'd100,
            8'h30+(value/8'd10)%8'd10,8'h30+value%8'd10,24'd0};
        prepared_len=prefix_len+3;
    end else if(active_page==2) begin
        prepared_suffix={8'h30+{1'b0,minutes_snapshot}/8'd10,
            8'h30+{1'b0,minutes_snapshot}%8'd10,8'h3a,
            8'h30+{2'd0,seconds_snapshot}/8'd10,8'h30+{2'd0,seconds_snapshot}%8'd10,8'h22};
        prepared_len=prefix_len+6;
    end else if(active_page==0) begin
        case(next_field)
            0:begin
                prepared_suffix={8'h30+{5'd0,image_count},8'h22,32'd0};
                prepared_len=prefix_len+2;
            end
            1:begin
                prepared_suffix={{5'b00110,audio_count},8'h22,32'd0};
                prepared_len=prefix_len+2;
            end
            default:begin
                prepared_suffix={
                    error_code==0?(initializing?8'h49:8'h4f):8'h45,
                    error_code==0?(initializing?8'h4e:8'h4b):(8'h30+{5'd0,error_code}),8'h22,24'd0};
                prepared_len=prefix_len+3;
            end
        endcase
    end
    prepared_len=prepared_len+3;
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        uart_tx<=1;command_sent_pulse<=0;tx_state<=TX_IDLE;
        active_page<=0;next_field<=0;refresh_count<=0;
        baud_count<=0;message_id<=0;message_suffix<=0;prefix_length<=0;suffix_length<=0;message_len<=0;byte_index<=0;
        bit_index<=0;shift_byte<=0;
        minutes_snapshot<=0;seconds_snapshot<=0;state_snapshot<=0;
        refresh_pending<=0;settings_seen<=0;
    end else begin
        command_sent_pulse<=0;
        settings_seen<=settings_live;
        if(refresh_request || settings_seen!=settings_live) refresh_pending<=1;
        if(refresh_count>=CLK_FREQ_HZ/4-1) refresh_count<=0;
        else refresh_count<=refresh_count+1'b1;
        case(tx_state)
            TX_IDLE: begin
                // Page changes cannot cut a command in half. Reload at next idle.
                if(page_id<=4 && active_page!=page_id) begin
                    active_page<=page_id;next_field<=0;refresh_pending<=0;
                    minutes_snapshot<=minutes;seconds_snapshot<=seconds;state_snapshot<=event_state;
                end else if(next_field<field_count) begin
                    message_id<=prepared_id;message_suffix<=prepared_suffix;
                    prefix_length<=prefix_len;suffix_length<=prepared_len-prefix_len-3;message_len<=prepared_len;
                    next_field<=next_field+1'b1;byte_index<=0;
                    shift_byte<=(active_page==1 ? 8'h73 : active_page==2 ? 8'h67 : 8'h68);bit_index<=0;
                    baud_count<=0;uart_tx<=0;tx_state<=TX_START;
                end else if(refresh_pending || (refresh_count==0 && active_page!=1)) begin
                    refresh_pending<=0;
                    next_field<=0;
                    minutes_snapshot<=minutes;seconds_snapshot<=seconds;state_snapshot<=event_state;
                end
            end
            TX_START: if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;uart_tx<=shift_byte[0];shift_byte<=shift_byte>>1;
                bit_index<=0;tx_state<=TX_DATA;
            end else baud_count<=baud_count+1'b1;
            TX_DATA: if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;
                if(bit_index==7) begin uart_tx<=1;tx_state<=TX_STOP;end
                else begin uart_tx<=shift_byte[0];shift_byte<=shift_byte>>1;bit_index<=bit_index+1'b1;end
            end else baud_count<=baud_count+1'b1;
            TX_STOP: if(baud_count==CLKS_PER_BIT-1) begin
                baud_count<=0;
                if(byte_index+1'b1<message_len) begin
                    if(byte_index+1'b1<prefix_length)
                        shift_byte<=prefix_byte;
                    else if(byte_index+1'b1<prefix_length+suffix_length)
                        shift_byte<=message_suffix[47-((byte_index+1'b1-prefix_length)*8) -: 8];
                    else shift_byte<=8'hff;
                    byte_index<=byte_index+1'b1;uart_tx<=0;tx_state<=TX_START;
                end else begin uart_tx<=1;command_sent_pulse<=1;tx_state<=TX_IDLE;end
            end else baud_count<=baud_count+1'b1;
            default:tx_state<=TX_IDLE;
        endcase
    end
end
endmodule

// Presentation-only policy, downstream of the existing SD status synchronizers.
module saixian_startup_error_policy(
 input clk,rst,initialized, input [2:0] fault,
 output [2:0] reported_error, output initializing);
reg boot_complete,previous_e02;
reg [1:0] boot_e02_count;
assign initializing=~boot_complete;
assign reported_error=(!boot_complete && fault==3'd2 && boot_e02_count<2)
                      ? 3'd0 : fault;
always @(posedge clk or posedge rst) begin
 if(rst) begin boot_complete<=0;previous_e02<=0;boot_e02_count<=0;end
 else begin
  previous_e02<=fault==3'd2;
  if(initialized) begin boot_complete<=1;boot_e02_count<=0;end
  else if(!boot_complete && fault==3'd2 && !previous_e02 && boot_e02_count<2)
   boot_e02_count<=boot_e02_count+1'b1;
 end
end
endmodule
