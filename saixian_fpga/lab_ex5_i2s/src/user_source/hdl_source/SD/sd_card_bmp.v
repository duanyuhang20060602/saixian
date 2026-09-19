module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd5
)(
    input clk, input rst,
    input prev_req_toggle, input next_req_toggle, input carousel_mode,
    input display_commit_toggle,
    output [3:0] state_code,
    output reg sd_init_done_o, output reg scan_done_o,
    output reg [2:0] image_count, output reg [2:0] error_code,
    output reg [15:0] source_width, output reg [15:0] source_height,
    output reg frame_ready_toggle, output reg [1:0] ready_buf_idx, output reg ready_slide_right,
    output reg [1:0] write_buf_idx,
    input [15:0] bmp_width, input [15:0] bmp_height,
    input write_finish_toggle,
    output write_req, input write_req_ack,
    output write_en, output [31:0] write_data,
    input [8:0] audio_fifo_wrusedw,
    output audio_pcm_we, output [31:0] audio_pcm_word,
    output reg audio_found_o,
    output SD_nCS, output SD_DCLK, output SD_MOSI, input SD_MISO
);

// Slow cards can need several seconds to leave idle after ACMD41. The error
// recovery path automatically resets and retries the controller.
localparam [31:0] INIT_TIMEOUT_CYCLES = CLK_FREQ_HZ * 8;
// Reading a 921654-byte BMP uses one CMD17 transaction per sector.  Some
// large/slow TF cards need more than five seconds even though every transfer
// is valid, so keep the timeout finite but allow adequate hardware margin.
localparam [31:0] LOAD_TIMEOUT_CYCLES = CLK_FREQ_HZ * 30;
localparam [31:0] AUTO_CYCLES = CLK_FREQ_HZ * 5;
localparam [32:0] SCAN_TIMEOUT_CYCLES = 64'd30 * CLK_FREQ_HZ;
localparam [31:0] SCAN_IDLE_CYCLES = CLK_FREQ_HZ * 5;
localparam [31:0] RECOVERY_CYCLES = CLK_FREQ_HZ * 2;

wire sd_sec_read, sd_sec_read_data_valid, sd_sec_read_end;
wire [31:0] sd_sec_read_addr;
wire [7:0] sd_sec_read_data;
wire bmp_sd_sec_read, bmp_sd_sec_read_data_valid, bmp_sd_sec_read_end;
wire [31:0] bmp_sd_sec_read_addr;
wire audio_sd_sec_read, audio_sd_sec_read_data_valid, audio_sd_sec_read_end;
wire [31:0] audio_sd_sec_read_addr;
wire bmp_data_wr_en, sd_init_done, bmp_ready, scan_done, scan_found_valid;
wire [23:0] bmp_data;
wire [31:0] scan_found_sector;
wire audio_scan_found_valid;
wire [31:0] audio_scan_found_sector, audio_scan_found_bytes;
wire [15:0] scan_found_width, scan_found_height;
wire [2:0] scan_found_total, init_stage;

reg scan_start_pulse, scan_stop_req, load_start_pulse, op_abort, scan_kicked;
reg [31:0] load_sector;
reg [31:0] image_sector0, image_sector1, image_sector2, image_sector3, image_sector4;
reg [15:0] image_width0, image_width1, image_width2, image_width3, image_width4;
reg [15:0] image_height0, image_height1, image_height2, image_height3, image_height4;
reg [15:0] pending_width, pending_height;
reg [2:0] current_image, pending_image, desired_image;
reg [1:0] current_buf;
reg load_busy, source_started, source_done, write_finish_seen, awaiting_commit, display_committed;
reg desired_slide_right, load_slide_right;
reg reload_first_after_scan;
reg [31:0] init_timer, load_timer, auto_timer, recovery_timer, scan_idle_timer;
reg [31:0] audio_start_sector, audio_data_bytes;
reg [32:0] scan_timer;
reg [2:0] prev_sync, next_sync, commit_sync, wrfin_sync;
reg [1:0] carousel_sync;

wire prev_pulse = prev_sync[2] ^ prev_sync[1];
wire next_pulse = next_sync[2] ^ next_sync[1];
wire commit_pulse = commit_sync[2] ^ commit_sync[1];
wire wrfin_pulse = wrfin_sync[2] ^ wrfin_sync[1];
wire carousel_on = carousel_sync[1];

assign write_en = bmp_data_wr_en;
assign write_data = {bmp_data[23:16], bmp_data[15:8], bmp_data[7:0], 8'b0};

function [2:0] next_index;
    input [2:0] cur; input [2:0] count;
    begin
        case (count)
            3'd2: next_index = (cur == 3'd1) ? 3'd0 : cur + 3'd1;
            3'd3: next_index = (cur == 3'd2) ? 3'd0 : cur + 3'd1;
            3'd4: next_index = (cur == 3'd3) ? 3'd0 : cur + 3'd1;
            3'd5: next_index = (cur == 3'd4) ? 3'd0 : cur + 3'd1;
            default: next_index = 3'd0;
        endcase
    end
endfunction

function [15:0] width_for;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: width_for = image_width0;
            3'd1: width_for = image_width1;
            3'd2: width_for = image_width2;
            3'd3: width_for = image_width3;
            3'd4: width_for = image_width4;
            default: width_for = image_width0;
        endcase
    end
endfunction

function [15:0] height_for;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: height_for = image_height0;
            3'd1: height_for = image_height1;
            3'd2: height_for = image_height2;
            3'd3: height_for = image_height3;
            3'd4: height_for = image_height4;
            default: height_for = image_height0;
        endcase
    end
endfunction

function [2:0] previous_index;
    input [2:0] cur; input [2:0] count;
    begin
        if (cur != 0) previous_index = cur - 3'd1;
        else if (count == 3'd5) previous_index = 3'd4;
        else if (count == 3'd4) previous_index = 3'd3;
        else if (count == 3'd3) previous_index = 3'd2;
        else if (count == 3'd2) previous_index = 3'd1;
        else previous_index = 3'd0;
    end
endfunction

function [31:0] sector_for;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: sector_for = image_sector0;
            3'd1: sector_for = image_sector1;
            3'd2: sector_for = image_sector2;
            3'd3: sector_for = image_sector3;
            3'd4: sector_for = image_sector4;
            default: sector_for = image_sector0;
        endcase
    end
endfunction
always @(posedge clk or posedge rst) begin
    if (rst) begin
        prev_sync <= 0; next_sync <= 0; commit_sync <= 0; wrfin_sync <= 0; carousel_sync <= 0;
    end else begin
        prev_sync <= {prev_sync[1:0], prev_req_toggle};
        next_sync <= {next_sync[1:0], next_req_toggle};
        commit_sync <= {commit_sync[1:0], display_commit_toggle};
        wrfin_sync <= {wrfin_sync[1:0], write_finish_toggle};
        carousel_sync <= {carousel_sync[0], carousel_mode};
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        scan_start_pulse <= 0; scan_stop_req <= 0; load_start_pulse <= 0; op_abort <= 0; load_sector <= 0;
        scan_kicked <= 0; image_sector0 <= 0; image_sector1 <= 0; image_sector2 <= 0; image_sector3 <= 0; image_sector4 <= 0;
        image_width0 <= 0; image_width1 <= 0; image_width2 <= 0; image_width3 <= 0; image_width4 <= 0;
        image_height0 <= 0; image_height1 <= 0; image_height2 <= 0; image_height3 <= 0; image_height4 <= 0;
        pending_width <= 0; pending_height <= 0; source_width <= 0; source_height <= 0;
        current_image <= 0; pending_image <= 0; desired_image <= 0; current_buf <= 0;
        ready_buf_idx <= 0; write_buf_idx <= 0;
        load_busy <= 0; source_started <= 0; source_done <= 0; write_finish_seen <= 0; awaiting_commit <= 0; display_committed <= 0;
        desired_slide_right <= 0; frame_ready_toggle <= 0;
        ready_slide_right <= 0; load_slide_right <= 0;
        reload_first_after_scan <= 0;
        sd_init_done_o <= 0; scan_done_o <= 0; image_count <= 0; error_code <= 0;
        audio_found_o <= 0; audio_start_sector <= 0; audio_data_bytes <= 0;
        init_timer <= 0; load_timer <= 0; auto_timer <= 0; recovery_timer <= 0; scan_timer <= 0; scan_idle_timer <= 0;
    end else begin
        scan_start_pulse <= 0; load_start_pulse <= 0; op_abort <= 0;
        sd_init_done_o <= sd_init_done;
        scan_done_o <= scan_done;

        // Retain the active framebuffer, but reset/reinitialize and rescan the
        // removable card after every SD error.  This makes reinsertion and
        // replacement recover without rebooting the FPGA.
        if (error_code != 0) begin
            if (recovery_timer < RECOVERY_CYCLES - 1)
                recovery_timer <= recovery_timer + 1'b1;
            else begin
                recovery_timer <= 0; op_abort <= 1; error_code <= 0;
                scan_kicked <= 0; image_count <= 0;
                audio_found_o <= 0; audio_start_sector <= 0; audio_data_bytes <= 0;
                scan_stop_req <= 0; scan_idle_timer <= 0;
                load_busy <= 0; awaiting_commit <= 0; desired_image <= 0;
                desired_slide_right <= 0;
                source_started <= 0; source_done <= 0; write_finish_seen <= 0;
                init_timer <= 0; scan_timer <= 0; load_timer <= 0;
                reload_first_after_scan <= display_committed;
            end
        end else begin
            recovery_timer <= 0;
        end

        if (!sd_init_done && error_code == 0) begin
            if (init_timer < INIT_TIMEOUT_CYCLES) init_timer <= init_timer + 1;
            else error_code <= (init_stage == 0) ? 3'd1 : 3'd2;
        end else if (sd_init_done) begin
            init_timer <= 0;
            if (error_code == 1 || error_code == 2) error_code <= 0;
        end

        if (sd_init_done && !scan_kicked && error_code == 0 && bmp_ready) begin
            scan_start_pulse <= 1;
            scan_kicked <= 1;
            scan_stop_req <= 0;
            scan_idle_timer <= 0;
            image_count <= 0;
            audio_found_o <= 0;
            desired_image <= 0;
            desired_slide_right <= 0;
            image_sector0 <= 0; image_sector1 <= 0; image_sector2 <= 0; image_sector3 <= 0; image_sector4 <= 0;
            image_width0 <= 0; image_width1 <= 0; image_width2 <= 0; image_width3 <= 0; image_width4 <= 0;
            image_height0 <= 0; image_height1 <= 0; image_height2 <= 0; image_height3 <= 0; image_height4 <= 0;
        end

        if (scan_kicked && !scan_done && error_code == 0) begin
            if (scan_timer < SCAN_TIMEOUT_CYCLES) scan_timer <= scan_timer + 1'b1;
            else begin op_abort <= 1; error_code <= 3'd3; end
        end else scan_timer <= 0;

        // Raw-sector scanning has no FAT directory to identify the last file.
        // After at least one valid BMP, finish cleanly when five seconds pass
        // without another match.  Do not reset the SD controller: the images
        // already collected can then be loaded into SDRAM immediately.
        if (scan_kicked && !scan_done && error_code == 0) begin
            if (scan_found_valid || audio_scan_found_valid)
                scan_idle_timer <= 0;
            else if (image_count != 0) begin
                if (scan_idle_timer < SCAN_IDLE_CYCLES - 1'b1)
                    scan_idle_timer <= scan_idle_timer + 1'b1;
                else
                    scan_stop_req <= 1'b1;
            end
        end else begin
            scan_idle_timer <= 0;
            scan_stop_req <= 0;
        end

        if (scan_found_valid) begin
            case (image_count)
                0: begin image_sector0 <= scan_found_sector; image_width0 <= scan_found_width; image_height0 <= scan_found_height; end
                1: begin image_sector1 <= scan_found_sector; image_width1 <= scan_found_width; image_height1 <= scan_found_height; end
                2: begin image_sector2 <= scan_found_sector; image_width2 <= scan_found_width; image_height2 <= scan_found_height; end
                3: begin image_sector3 <= scan_found_sector; image_width3 <= scan_found_width; image_height3 <= scan_found_height; end
                4: begin image_sector4 <= scan_found_sector; image_width4 <= scan_found_width; image_height4 <= scan_found_height; end
                default: ;
            endcase
            if (image_count < 5) image_count <= image_count + 1;
        end

        if (audio_scan_found_valid) begin
            audio_found_o <= 1'b1;
            audio_start_sector <= audio_scan_found_sector;
            audio_data_bytes <= audio_scan_found_bytes;
        end

        if (scan_done && !scan_found_valid && image_count == 0 && scan_kicked && error_code == 0) error_code <= 3'd3;

        // Track the desired image independently from the visible one. A TF
        // transfer can take seconds, so presses received while busy must update
        // the target instead of being collapsed into one pending direction bit.
        if (prev_pulse && carousel_on && scan_done && image_count > 1) begin
            desired_image <= previous_index(desired_image, image_count);
            desired_slide_right <= 1;
            auto_timer <= 0;
        end else if (next_pulse && carousel_on && scan_done && image_count > 1) begin
            desired_image <= next_index(desired_image, image_count);
            desired_slide_right <= 0;
            auto_timer <= 0;
        end else if (carousel_on && scan_done && image_count > 1 &&
                     display_committed && !load_busy && !awaiting_commit &&
                     (desired_image == current_image)) begin
            if (auto_timer == AUTO_CYCLES - 1) begin
                auto_timer <= 0;
                desired_image <= next_index(current_image, image_count);
                desired_slide_right <= 0;
            end else auto_timer <= auto_timer + 1;
        end else if (!carousel_on) begin
            auto_timer <= 0;
        end

        if (scan_done && image_count != 0 && !load_busy && !awaiting_commit && bmp_ready) begin
            if (reload_first_after_scan && display_committed) begin
                pending_image <= 0; load_sector <= image_sector0;
                write_buf_idx <= (current_buf == 0) ? 2'd1 : 2'd0;
                pending_width <= image_width0; pending_height <= image_height0;
                load_slide_right <= 0;
                load_start_pulse <= 1; load_busy <= 1; source_started <= 0; source_done <= 0; write_finish_seen <= 0; load_timer <= 0;
                reload_first_after_scan <= 0;
            end else if (!display_committed) begin
                pending_image <= 0; load_sector <= image_sector0; write_buf_idx <= 0;
                pending_width <= image_width0; pending_height <= image_height0;
                load_slide_right <= 0;
                load_start_pulse <= 1; load_busy <= 1; source_started <= 0; source_done <= 0; write_finish_seen <= 0; load_timer <= 0;
            end else if (desired_image != current_image) begin
                pending_image <= desired_image;
                load_sector <= sector_for(desired_image);
                pending_width <= width_for(desired_image);
                pending_height <= height_for(desired_image);
                write_buf_idx <= (current_buf == 0) ? 2'd1 : 2'd0;
                load_slide_right <= desired_slide_right;
                load_start_pulse <= 1; load_busy <= 1; source_started <= 0; source_done <= 0; write_finish_seen <= 0;
                load_timer <= 0;
            end
        end

        if (load_busy) begin
            if (!bmp_ready) source_started <= 1;
            if (source_started && bmp_ready) source_done <= 1;
            // write_finish crosses from the SDRAM clock domain as a toggle.
            // Latch it so it cannot be lost when it arrives one SD clock before
            // bmp_ready returns high at the end of the source transfer.
            if (wrfin_pulse) write_finish_seen <= 1;
            if (load_timer < LOAD_TIMEOUT_CYCLES) load_timer <= load_timer + 1;
            else begin load_busy <= 0; op_abort <= 1; error_code <= 3'd4; end
        end

        if (load_busy &&
            (source_done || (source_started && bmp_ready)) &&
            (write_finish_seen || wrfin_pulse)) begin
            load_busy <= 0; awaiting_commit <= 1; ready_buf_idx <= write_buf_idx;
            ready_slide_right <= load_slide_right;
            frame_ready_toggle <= ~frame_ready_toggle;
        end

        if (awaiting_commit && commit_pulse) begin
            awaiting_commit <= 0; display_committed <= 1; current_buf <= ready_buf_idx; current_image <= pending_image;
            source_width <= pending_width; source_height <= pending_height; auto_timer <= 0;
        end
    end
end

bmp_read u_bmp_read(
    .clk(clk), .rst(rst), .op_abort(op_abort), .ready(bmp_ready),
    .scan_start(scan_start_pulse), .scan_stop(scan_stop_req), .scan_start_sector(SCAN_START_SECTOR),
    .scan_max_sector(SCAN_MAX_SECTOR), .scan_target_count(SCAN_TARGET_COUNT),
    .scan_done(scan_done), .scan_found_valid(scan_found_valid),
    .scan_found_sector(scan_found_sector), .scan_found_total(scan_found_total),
    .scan_found_width(scan_found_width), .scan_found_height(scan_found_height),
    .audio_found_valid(audio_scan_found_valid), .audio_found_sector(audio_scan_found_sector),
    .audio_found_bytes(audio_scan_found_bytes),
    .load_start(load_start_pulse), .load_sector(load_sector),
    .sd_init_done(sd_init_done), .state_code(state_code), .bmp_width(bmp_width), .bmp_height(bmp_height),
    .write_req(write_req), .write_req_ack(write_req_ack),
    .sd_sec_read(bmp_sd_sec_read), .sd_sec_read_addr(bmp_sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data), .sd_sec_read_data_valid(bmp_sd_sec_read_data_valid),
    .sd_sec_read_end(bmp_sd_sec_read_end), .bmp_data_wr_en(bmp_data_wr_en), .bmp_data(bmp_data)
);

saixian_sd_audio_stream u_audio_stream(
    .clk(clk), .rst(rst | op_abort),
    .enable(audio_found_o && sd_init_done),
    .start_sector(audio_start_sector), .data_bytes(audio_data_bytes),
    .fifo_wrusedw(audio_fifo_wrusedw),
    .sd_sec_read(audio_sd_sec_read), .sd_sec_read_addr(audio_sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data), .sd_sec_read_data_valid(audio_sd_sec_read_data_valid),
    .sd_sec_read_end(audio_sd_sec_read_end),
    .pcm_we(audio_pcm_we), .pcm_word(audio_pcm_word)
);

// One physical SPI reader serves both clients. Audio receives priority only
// when its FIFO needs a complete 512-byte refill; every grant lasts exactly
// one CMD17 transaction, so BMP loading still advances between audio sectors.
reg [1:0] read_owner;
reg [31:0] read_addr_latched;
always @(posedge clk or posedge rst) begin
    if (rst || op_abort) begin
        read_owner <= 2'd0;
        read_addr_latched <= 32'd0;
    end else if (read_owner == 2'd0) begin
        if (audio_sd_sec_read) begin
            read_owner <= 2'd2;
            read_addr_latched <= audio_sd_sec_read_addr;
        end else if (bmp_sd_sec_read) begin
            read_owner <= 2'd1;
            read_addr_latched <= bmp_sd_sec_read_addr;
        end
    end else if (sd_sec_read_end) begin
        read_owner <= 2'd0;
    end
end

assign sd_sec_read = (read_owner != 2'd0);
assign sd_sec_read_addr = read_addr_latched;
assign bmp_sd_sec_read_data_valid = sd_sec_read_data_valid && (read_owner == 2'd1);
assign bmp_sd_sec_read_end = sd_sec_read_end && (read_owner == 2'd1);
assign audio_sd_sec_read_data_valid = sd_sec_read_data_valid && (read_owner == 2'd2);
assign audio_sd_sec_read_end = sd_sec_read_end && (read_owner == 2'd2);

// 100 MHz / ((2 + 2) * 2) = 12.5 MHz for extra MISO timing margin.
sd_card_top #(
    .SPI_LOW_SPEED_DIV(248),
    .SPI_HIGH_SPEED_DIV(2)
) u_sd_card_top(
    .clk(clk), .rst(rst | op_abort), .SD_nCS(SD_nCS), .SD_DCLK(SD_DCLK), .SD_MOSI(SD_MOSI), .SD_MISO(SD_MISO),
    .sd_init_done(sd_init_done), .init_stage(init_stage),
    .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr), .sd_sec_read_data(sd_sec_read_data),
    .sd_sec_read_data_valid(sd_sec_read_data_valid), .sd_sec_read_end(sd_sec_read_end),
    .sd_sec_write(1'b0), .sd_sec_write_addr(32'd0), .sd_sec_write_data(8'd0),
    .sd_sec_write_data_req(), .sd_sec_write_end()
);

endmodule

module saixian_sd_audio_stream(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [31:0] start_sector,
    input  wire [31:0] data_bytes,
    input  wire [8:0]  fifo_wrusedw,
    output reg         sd_sec_read,
    output reg  [31:0] sd_sec_read_addr,
    input  wire [7:0]  sd_sec_read_data,
    input  wire        sd_sec_read_data_valid,
    input  wire        sd_sec_read_end,
    output reg         pcm_we,
    output reg  [31:0] pcm_word
);

reg initialized;
reg [31:0] current_sector;
reg [31:0] bytes_remaining;
reg [9:0] sector_byte_count;
reg [1:0] pcm_byte_index;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        initialized <= 1'b0;
        current_sector <= 32'd0;
        bytes_remaining <= 32'd0;
        sector_byte_count <= 10'd0;
        pcm_byte_index <= 2'd0;
        sd_sec_read <= 1'b0;
        sd_sec_read_addr <= 32'd0;
        pcm_we <= 1'b0;
        pcm_word <= 32'd0;
    end else begin
        pcm_we <= 1'b0;

        if (!enable) begin
            initialized <= 1'b0;
            sd_sec_read <= 1'b0;
            current_sector <= start_sector;
            bytes_remaining <= data_bytes;
            sector_byte_count <= 10'd0;
            pcm_byte_index <= 2'd0;
        end else if (!initialized) begin
            initialized <= 1'b1;
            current_sector <= start_sector;
            bytes_remaining <= data_bytes;
            sd_sec_read_addr <= start_sector;
            sector_byte_count <= 10'd0;
            pcm_byte_index <= 2'd0;
        end else begin
            // A sector contains 128 stereo frames. Starting only below 257
            // samples guarantees that the 512-entry FIFO cannot overflow.
            if (!sd_sec_read && (fifo_wrusedw <= 9'd256) && (data_bytes != 0)) begin
                sd_sec_read <= 1'b1;
                sd_sec_read_addr <= current_sector;
                sector_byte_count <= 10'd0;
                pcm_byte_index <= 2'd0;
            end

            if (sd_sec_read_data_valid &&
                ({22'd0,sector_byte_count} < bytes_remaining)) begin
                sector_byte_count <= sector_byte_count + 10'd1;
                case (pcm_byte_index)
                    2'd0: begin pcm_word[7:0] <= sd_sec_read_data; pcm_byte_index <= 2'd1; end
                    2'd1: begin pcm_word[15:8] <= sd_sec_read_data; pcm_byte_index <= 2'd2; end
                    2'd2: begin pcm_word[23:16] <= sd_sec_read_data; pcm_byte_index <= 2'd3; end
                    2'd3: begin
                        pcm_word[31:24] <= sd_sec_read_data;
                        pcm_byte_index <= 2'd0;
                        pcm_we <= 1'b1;
                    end
                endcase
            end

            if (sd_sec_read_end) begin
                sd_sec_read <= 1'b0;
                sector_byte_count <= 10'd0;
                pcm_byte_index <= 2'd0;
                if (bytes_remaining <= 32'd512) begin
                    current_sector <= start_sector;
                    bytes_remaining <= data_bytes;
                    sd_sec_read_addr <= start_sector;
                end else begin
                    current_sector <= current_sector + 32'd1;
                    bytes_remaining <= bytes_remaining - 32'd512;
                    sd_sec_read_addr <= current_sector + 32'd1;
                end
            end
        end
    end
end

endmodule
