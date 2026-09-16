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
parameter [20:0] FRAME_PIXELS = 21'd307200;
parameter [20:0] BUF0_ADDR = 21'd0;
parameter BUF1_ADDR = FRAME_PIXELS;

wire sd_card_clk, ext_mem_clk, ext_mem_clk_sft, video_clk, hdmi_5x_clk;
wire sys_pll_lock, video_pll_lock;
wire pll_locked = sys_pll_lock & video_pll_lock;
reg [22:0] por_count;
wire reset_request = ~por_count[22];
wire rst_clk, rst_sd, rst_mem, rst_video, rst_hdmi;

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
saixian_reset_sync u_rst_video(.clk(video_clk),    .arst(reset_request), .rst(rst_video));
saixian_reset_sync u_rst_hdmi (.clk(hdmi_5x_clk),  .arst(reset_request), .rst(rst_hdmi));

wire key1_press, key2_press, key3_press, key4_press;
saixian_key_debounce #(.CLK_FREQ_HZ(25_000_000),.DEBOUNCE_MS(20)) u_key1(.clk(video_clk),.rst(rst_video),.key_n(key[0]),.press_pulse(key1_press));
saixian_key_debounce #(.CLK_FREQ_HZ(25_000_000),.DEBOUNCE_MS(20)) u_key2(.clk(video_clk),.rst(rst_video),.key_n(key[1]),.press_pulse(key2_press));
saixian_key_debounce #(.CLK_FREQ_HZ(25_000_000),.DEBOUNCE_MS(20)) u_key3(.clk(video_clk),.rst(rst_video),.key_n(key[2]),.press_pulse(key3_press));
saixian_key_debounce #(.CLK_FREQ_HZ(25_000_000),.DEBOUNCE_MS(20)) u_key4(.clk(video_clk),.rst(rst_video),.key_n(key[3]),.press_pulse(key4_press));

wire [1:0] project_select;
saixian_switch_filter #(.CLK_FREQ_HZ(25_000_000),.FILTER_MS(20)) u_project_switch(
    .clk(video_clk),.rst(rst_video),.switch_in(sw),.switch_out(project_select)
);

wire hs0, vs0, de0, hs, vs, de;
wire video_read_req, video_read_req_ack, video_read_en;
wire video_read_empty, video_underflow, display_valid;
wire [31:0] video_read_data;
wire [23:0] video_rgb_raw;
wire [9:0] pixel_x;
wire [8:0] pixel_y;
wire frame_tick;

video_timing_data u_timing(.video_clk(video_clk),.rst(rst_video),.read_req(video_read_req),.read_req_ack(video_read_req_ack),.hs(hs0),.vs(vs0),.de(de0));
video_delay u_delay(.video_clk(video_clk),.rst(rst_video),.read_en(video_read_en),.read_data(video_read_data[31:8]),
    .read_empty(video_read_empty),.display_valid(display_valid),.underflow_latched(video_underflow),
    .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(video_rgb_raw));
saixian_video_tracker u_tracker(.clk(video_clk),.rst(rst_video),.vs(vs),.de(de),.x(pixel_x),.y(pixel_y),.frame_tick(frame_tick));

wire hmi_start_pulse, hmi_pause_pulse, hmi_finish_pulse;
wire hmi_prev_pulse, hmi_next_pulse;
wire hmi_setting_valid, hmi_reset_defaults, hmi_frame_error;
wire [2:0] hmi_setting_id;
wire [7:0] hmi_setting_value;
saixian_hmi_uart #(.CLK_FREQ_HZ(25_000_000),.BAUD_RATE(115_200)) u_hmi_uart(
    .clk(video_clk),.rst(rst_video),.uart_rx(hmi_uart_rx),
    .start_pulse(hmi_start_pulse),.pause_pulse(hmi_pause_pulse),
    .finish_pulse(hmi_finish_pulse),.prev_pulse(hmi_prev_pulse),.next_pulse(hmi_next_pulse),
    .setting_valid(hmi_setting_valid),.setting_id(hmi_setting_id),.setting_value(hmi_setting_value),
    .reset_defaults_pulse(hmi_reset_defaults),.frame_error_pulse(hmi_frame_error)
);
// Bidirectional status updates can be added later. Keep FPGA TX at the UART
// idle level for this screen-to-FPGA control revision.
assign hmi_uart_tx = 1'b1;

wire [3:0] event_state;
wire [1:0] project_id;
wire [6:0] minutes;
wire [5:0] seconds;
wire [3:0] countdown_value, cue_event;
wire carousel_mode;
wire settings_mode;
wire [1:0] setting_item;
wire [3:0] volume_setting, brightness_setting, contrast_setting, saturation_setting;
wire [1:0] sharpness_setting;
wire [7:0] audio_level;

saixian_settings_controller u_settings(
    .clk(video_clk),.rst(rst_video),.carousel_mode(carousel_mode),
    .key_next_item(key1_press),.key_decrease(key2_press),
    .key_enter_exit(key3_press),.key_increase(key4_press),
    .hmi_setting_valid(hmi_setting_valid),.hmi_setting_id(hmi_setting_id),
    .hmi_setting_value(hmi_setting_value),.hmi_reset_defaults(hmi_reset_defaults),
    .settings_mode(settings_mode),.setting_item(setting_item),
    .volume_setting(volume_setting),.brightness_setting(brightness_setting),
    .contrast_setting(contrast_setting),.saturation_setting(saturation_setting),
    .sharpness_setting(sharpness_setting)
);

saixian_event_controller u_event(
    .clk(video_clk),.rst(rst_video),.frame_start(frame_tick),
    .key_start((key1_press & ~settings_mode) | hmi_start_pulse),
    .key_pause((key2_press & ~settings_mode) | hmi_pause_pulse),
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
    else if (carousel_mode && !settings_mode) begin
        if (key2_press | hmi_prev_pulse) prev_req_toggle <= ~prev_req_toggle;
        if (key4_press | hmi_next_pulse) next_req_toggle <= ~next_req_toggle;
    end
end

wire [3:0] sd_state_code;
wire sd_init_done, scan_done;
wire [2:0] image_count, sd_error;
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
wire [9:0] slide_offset;
wire [5:0] transition_level;
wire sd_card_write_req, sd_card_write_req_ack, sd_card_write_en;
wire [31:0] sd_card_write_data;
wire frame_write_finish;
reg frame_write_toggle_mem;
wire write_fifo_full;
reg write_overflow_latched;

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

sd_card_bmp #(.CLK_FREQ_HZ(100_000_000),.SCAN_START_SECTOR(0),.SCAN_MAX_SECTOR(131071),.SCAN_TARGET_COUNT(4)) u_sd_bmp(
    .clk(sd_card_clk),.rst(rst_sd),.prev_req_toggle(prev_req_toggle),.next_req_toggle(next_req_toggle),
    .carousel_mode(carousel_mode && !settings_mode),.display_commit_toggle(frame_commit_toggle),.state_code(sd_state_code),
    .sd_init_done_o(sd_init_done),.scan_done_o(scan_done),.image_count(image_count),.error_code(sd_error),
    .source_width(source_width_sd),.source_height(source_height_sd),
    .frame_ready_toggle(frame_ready_toggle),.ready_buf_idx(ready_buf_idx),.ready_slide_right(ready_slide_right),.write_buf_idx(write_buf_idx),
    .bmp_width(16'd640),.bmp_height(16'd480),.write_finish_toggle(frame_write_toggle_mem),
    .write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
    .SD_nCS(sd_ncs),.SD_DCLK(sd_dclk),.SD_MOSI(sd_mosi),.SD_MISO(sd_miso)
);

saixian_transition u_transition(
    .clk(video_clk),.rst(rst_video),.frame_tick(frame_tick),.frame_ready_toggle(frame_ready_toggle),.ready_buf_idx(ready_buf_idx),
    .ready_slide_right(ready_slide_right),.active_buf_idx(active_buf_idx),.slide_new_buf_idx(slide_new_buf_idx),
    .frame_commit_toggle(frame_commit_toggle),.display_valid(display_valid),.transition_active(transition_active),
    .slide_offset(slide_offset),.slide_right(slide_right),.transition_level(transition_level)
);

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        sd_error_sync0 <= 0; sd_error_sync1 <= 0;
        source_width_sync0 <= 0; source_width_sync1 <= 0;
        source_height_sync0 <= 0; source_height_sync1 <= 0;
    end else begin
        sd_error_sync0 <= sd_error; sd_error_sync1 <= sd_error_sync0;
        source_width_sync0 <= source_width_sd; source_width_sync1 <= source_width_sync0;
        source_height_sync0 <= source_height_sd; source_height_sync1 <= source_height_sync0;
    end
end

wire Sdr_init_done, Sdr_init_ref_vld, Sdr_busy;
wire App_rd_en, Sdr_rd_en, App_wr_en;
wire [ADDR_BITS-1:0] App_rd_addr, App_wr_addr;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout, App_wr_din;
wire [3:0] App_wr_dm;

frame_read_write #(.WRITE_V_FLIP(1),.FRAME_WIDTH(640),.FRAME_HEIGHT(480)) u_frame_rw(
    .mem_clk(ext_mem_clk),.rst(rst_mem),.Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),
    .App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),
    .read_clk(video_clk),.read_req(video_read_req),.read_req_ack(video_read_req_ack),.read_finish(),
    .read_addr_0(BUF0_ADDR),.read_addr_1(BUF1_ADDR),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(active_buf_idx),
    .read_len(FRAME_PIXELS),.read_en(video_read_en),.read_data(video_read_data),.read_fifo_empty(video_read_empty),
    .slide_active(transition_active),.slide_old_index(active_buf_idx),.slide_new_index(slide_new_buf_idx),
    .slide_offset(slide_offset),.slide_right(slide_right),
    .App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_din(App_wr_din),.App_wr_dm(App_wr_dm),
    .write_clk(sd_card_clk),.write_req(sd_card_write_req),.write_req_ack(sd_card_write_req_ack),.write_finish(frame_write_finish),
    .write_addr_0(BUF0_ADDR),.write_addr_1(BUF1_ADDR),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(write_buf_idx),
    .write_len(FRAME_PIXELS),.write_en(sd_card_write_en),.write_data(sd_card_write_data),
    .write_fifo_full(write_fifo_full)
);

sdram u_sdram(.Clk(ext_mem_clk),.Clk_sft(ext_mem_clk_sft),.Rst(rst_mem),.Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),.App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),
    .App_wr_dm(App_wr_dm),.App_wr_din(App_wr_din),.App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),
    .Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout));

wire audio_valid;
wire [23:0] audio_left_raw, audio_right_raw;
wire [7:0] audio_level_raw;
wire spectrum_active;
wire [4:0] spectrum_tone_bin;
wire [23:0] audio_left_data, audio_right_data;
wire acr_valid;
wire [19:0] acr_cts, acr_n;
saixian_audio_cue u_cue(.clk(video_clk),.rst(rst_video),.cue_event(cue_event),.audio_valid(audio_valid),
    .audio_left(audio_left_raw),.audio_right(audio_right_raw),.audio_level(audio_level_raw),
    .spectrum_active(spectrum_active),.spectrum_tone_bin(spectrum_tone_bin));
saixian_audio_volume u_volume(.volume_setting(volume_setting),.audio_left_in(audio_left_raw),
    .audio_right_in(audio_right_raw),.level_in(audio_level_raw),.audio_left_out(audio_left_data),
    .audio_right_out(audio_right_data),.level_out(audio_level));
audio_arc_calculate #(.ACR_N(6144)) u_acr(.I_clk(video_clk),.I_rst(rst_video),.I_audio_valid(audio_valid),
    .O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));

reg [1:0] hpd_sync;
reg hpd_present, hpd_last, edid_seen, edid_failed;
reg [18:0] hpd_debounce_timer;
reg [25:0] edid_timer;
reg edid_trig;
wire edid_valid;
wire [7:0] edid_data;
wire hdmi_error = !hpd_present || edid_failed;
wire [2:0] error_code = (sd_error_sync1 != 0) ? sd_error_sync1 : (hdmi_error ? 3'd5 : 3'd0);

always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        hpd_sync <= 0; hpd_present <= 0; hpd_last <= 0; hpd_debounce_timer <= 0;
        edid_seen <= 0; edid_failed <= 0; edid_timer <= 0; edid_trig <= 0;
    end else begin
        hpd_sync <= {hpd_sync[0],hdmi_hpd};
        // Accept plug/unplug only after 20 ms of stable HPD.
        if (hpd_sync[1] == hpd_present)
            hpd_debounce_timer <= 0;
        else if (hpd_debounce_timer >= 19'd499_999) begin
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
        end else if (!edid_seen && (edid_timer >= 26'd49_999_999)) begin
            // Report E05 and retry EDID every two seconds without a reboot.
            edid_failed <= 1; edid_trig <= 1; edid_timer <= 0;
        end else if (!edid_seen)
            edid_timer <= edid_timer + 1'b1;
    end
end

wire [23:0] adjusted_rgb;
saixian_picture_adjust u_picture_adjust(.clk(video_clk),.rst(rst_video),.de(de),.x(pixel_x),
    .rgb_in(video_rgb_raw),.brightness_setting(brightness_setting),.contrast_setting(contrast_setting),
    .saturation_setting(saturation_setting),.sharpness_setting(sharpness_setting),.rgb_out(adjusted_rgb));

wire [23:0] osd_rgb;
saixian_osd_overlay u_osd(.de(de),.x(pixel_x),.y(pixel_y),.rgb_in(adjusted_rgb),.display_valid(display_valid),
    .loading_phase(loading_phase),
    .state(event_state),.project_id(carousel_mode ? project_select : project_id),.minutes(minutes),.seconds(seconds),.countdown_value(countdown_value),
    .ticker_x(ticker_x),
    .source_width_bcd(source_width_bcd),.source_height_bcd(source_height_bcd),
    .error_code(error_code),.transition_active(transition_active),.transition_level(transition_level),
    .audio_level(audio_level),.spectrum_active(spectrum_active),.spectrum_tone_bin(spectrum_tone_bin),
    .settings_mode(settings_mode),.setting_item(setting_item),
    .volume_setting(volume_setting),.brightness_setting(brightness_setting),
    .contrast_setting(contrast_setting),.sharpness_setting(sharpness_setting),.rgb_out(osd_rgb));

// Register RGB and its timing controls together before AXI conversion.  This
// preserves pixel alignment while cutting the long combinational OSD path.
reg [23:0] osd_rgb_pipe;
reg        de_pipe;
reg        vs_pipe;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin
        osd_rgb_pipe <= 24'd0;
        de_pipe      <= 1'b0;
        vs_pipe      <= 1'b0;
    end else begin
        osd_rgb_pipe <= osd_rgb;
        de_pipe      <= de;
        vs_pipe      <= vs;
    end
end

wire axis_s_user, axis_s_valid, axis_s_last, axis_s_ready;
wire [23:0] axis_s_data;
video_rgb_to_axis_640x480 u_axis(.I_clk(video_clk),.I_rst(rst_video),.I_vs(vs_pipe),.I_de(de_pipe),.I_rgb(osd_rgb_pipe),
    .O_video_user(axis_s_user),.O_video_valid(axis_s_valid),.O_video_last(axis_s_last),.O_video_data(axis_s_data));

wire [9:0] tmds_ch0_data, tmds_ch1_data, tmds_ch2_data, tmds_clk_data;
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
    .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),.VIDEO_VIC(1),
    .VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)
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

wire [6:0] seg_code;
seg_decoder u_seg_decode(.bin_data(error_code != 0 ? {1'b0,error_code} : event_state),.seg_data(seg_code));
seg_scan u_seg(.clk(clk),.rst_n(~rst_clk),.seg_sel(seg_sel),.seg_data(seg_data),
    .seg_data_0({1'b1,seg_code}),.seg_data_1({1'b1,7'b1111111}),.seg_data_2({1'b1,7'b1111111}),
    .seg_data_3({1'b1,7'b1111111}),.seg_data_4({1'b1,7'b1111111}),.seg_data_5({1'b1,7'b1111111}));

assign led[0] = carousel_mode;
assign led[1] = sd_init_done;
assign led[2] = hpd_present;
// LED4 indicates an E-code, video FIFO underflow, or write FIFO overflow.
assign led[3] = (error_code != 0) | video_underflow | write_overflow_latched;

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
    parameter integer TIMEOUT_SECONDS = 15
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
    output reg [1:0]  setting_item,
    output reg [3:0]  volume_setting,
    output reg [3:0]  brightness_setting,
    output reg [3:0]  contrast_setting,
    output reg [3:0]  saturation_setting,
    output reg [1:0]  sharpness_setting
);
localparam [28:0] TIMEOUT_CYCLES = CLK_FREQ_HZ * TIMEOUT_SECONDS;
reg [28:0] idle_timer;

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
        setting_item       <= 2'd0;
        volume_setting     <= 4'd5;
        brightness_setting <= 4'd4;
        contrast_setting   <= 4'd4;
        saturation_setting <= 4'd4;
        sharpness_setting  <= 2'd1;
        idle_timer         <= 29'd0;
    end else if (hmi_reset_defaults) begin
        volume_setting     <= 4'd5;
        brightness_setting <= 4'd4;
        contrast_setting   <= 4'd4;
        saturation_setting <= 4'd4;
        sharpness_setting  <= 2'd1;
        idle_timer         <= 29'd0;
    end else if (hmi_setting_valid) begin
        idle_timer <= 29'd0;
        case (hmi_setting_id)
            3'd0: sharpness_setting  <= (hmi_setting_value > 3) ? 2'd3 : hmi_setting_value[1:0];
            3'd1: brightness_setting <= quantize_percent(hmi_setting_value);
            3'd2: contrast_setting   <= quantize_percent(hmi_setting_value);
            3'd3: saturation_setting <= quantize_percent(hmi_setting_value);
            3'd4: volume_setting     <= quantize_percent(hmi_setting_value);
            default: ;
        endcase
    end else if (!carousel_mode) begin
        settings_mode <= 1'b0;
        idle_timer    <= 29'd0;
    end else if (!settings_mode) begin
        idle_timer <= 29'd0;
        if (key_enter_exit) begin
            settings_mode <= 1'b1;
            setting_item  <= 2'd0;
        end
    end else begin
        if (key_next_item || key_decrease || key_enter_exit || key_increase)
            idle_timer <= 29'd0;
        else if (idle_timer >= TIMEOUT_CYCLES - 1'b1) begin
            idle_timer    <= 29'd0;
            settings_mode <= 1'b0;
        end else
            idle_timer <= idle_timer + 1'b1;

        if (key_enter_exit)
            settings_mode <= 1'b0;
        else if (key_next_item)
            setting_item <= setting_item + 1'b1;
        else if (key_decrease) begin
            case (setting_item)
                2'd0: if (volume_setting     != 0) volume_setting     <= volume_setting - 1'b1;
                2'd1: if (brightness_setting != 0) brightness_setting <= brightness_setting - 1'b1;
                2'd2: if (contrast_setting   != 0) contrast_setting   <= contrast_setting - 1'b1;
                2'd3: if (sharpness_setting  != 0) sharpness_setting  <= sharpness_setting - 1'b1;
            endcase
        end else if (key_increase) begin
            case (setting_item)
                2'd0: if (volume_setting     < 8) volume_setting     <= volume_setting + 1'b1;
                2'd1: if (brightness_setting < 8) brightness_setting <= brightness_setting + 1'b1;
                2'd2: if (contrast_setting   < 8) contrast_setting   <= contrast_setting + 1'b1;
                2'd3: if (sharpness_setting  < 3) sharpness_setting  <= sharpness_setting + 1'b1;
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
