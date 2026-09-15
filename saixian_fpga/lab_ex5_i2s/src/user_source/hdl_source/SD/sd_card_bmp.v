module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4
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
    output SD_nCS, output SD_DCLK, output SD_MOSI, input SD_MISO
);

localparam [31:0] INIT_TIMEOUT_CYCLES = CLK_FREQ_HZ * 3;
// Reading a 921654-byte BMP uses one CMD17 transaction per sector.  Some
// large/slow TF cards need more than five seconds even though every transfer
// is valid, so keep the timeout finite but allow adequate hardware margin.
localparam [31:0] LOAD_TIMEOUT_CYCLES = CLK_FREQ_HZ * 30;
localparam [31:0] AUTO_CYCLES = CLK_FREQ_HZ * 5;
localparam [32:0] SCAN_TIMEOUT_CYCLES = 64'd60 * CLK_FREQ_HZ;
localparam [31:0] RECOVERY_CYCLES = CLK_FREQ_HZ * 2;

wire sd_sec_read, sd_sec_read_data_valid, sd_sec_read_end;
wire [31:0] sd_sec_read_addr;
wire [7:0] sd_sec_read_data;
wire bmp_data_wr_en, sd_init_done, bmp_ready, scan_done, scan_found_valid;
wire [23:0] bmp_data;
wire [31:0] scan_found_sector;
wire [15:0] scan_found_width, scan_found_height;
wire [2:0] scan_found_total, init_stage;

reg scan_start_pulse, load_start_pulse, op_abort, scan_kicked;
reg [31:0] load_sector;
reg [31:0] image_sector0, image_sector1, image_sector2, image_sector3;
reg [15:0] image_width0, image_width1, image_width2, image_width3;
reg [15:0] image_height0, image_height1, image_height2, image_height3;
reg [15:0] pending_width, pending_height;
reg [1:0] current_image, pending_image, desired_image, current_buf;
reg load_busy, source_started, source_done, write_finish_seen, awaiting_commit, display_committed;
reg desired_slide_right, load_slide_right;
reg reload_first_after_scan;
reg [31:0] init_timer, load_timer, auto_timer, recovery_timer;
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

function [1:0] next_index;
    input [1:0] cur; input [2:0] count;
    begin
        case (count)
            3'd2: next_index = (cur == 2'd1) ? 2'd0 : cur + 2'd1;
            3'd3: next_index = (cur == 2'd2) ? 2'd0 : cur + 2'd1;
            3'd4: next_index = (cur == 2'd3) ? 2'd0 : cur + 2'd1;
            default: next_index = 2'd0;
        endcase
    end
endfunction

function [15:0] width_for;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: width_for = image_width0;
            2'd1: width_for = image_width1;
            2'd2: width_for = image_width2;
            default: width_for = image_width3;
        endcase
    end
endfunction

function [15:0] height_for;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: height_for = image_height0;
            2'd1: height_for = image_height1;
            2'd2: height_for = image_height2;
            default: height_for = image_height3;
        endcase
    end
endfunction

function [1:0] previous_index;
    input [1:0] cur; input [2:0] count;
    begin
        if (cur != 0) previous_index = cur - 2'd1;
        else if (count == 3'd4) previous_index = 2'd3;
        else if (count == 3'd3) previous_index = 2'd2;
        else if (count == 3'd2) previous_index = 2'd1;
        else previous_index = 2'd0;
    end
endfunction

function [31:0] sector_for;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_for = image_sector0;
            2'd1: sector_for = image_sector1;
            2'd2: sector_for = image_sector2;
            default: sector_for = image_sector3;
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
        scan_start_pulse <= 0; load_start_pulse <= 0; op_abort <= 0; load_sector <= 0;
        scan_kicked <= 0; image_sector0 <= 0; image_sector1 <= 0; image_sector2 <= 0; image_sector3 <= 0;
        image_width0 <= 0; image_width1 <= 0; image_width2 <= 0; image_width3 <= 0;
        image_height0 <= 0; image_height1 <= 0; image_height2 <= 0; image_height3 <= 0;
        pending_width <= 0; pending_height <= 0; source_width <= 0; source_height <= 0;
        current_image <= 0; pending_image <= 0; desired_image <= 0; current_buf <= 0;
        ready_buf_idx <= 0; write_buf_idx <= 0;
        load_busy <= 0; source_started <= 0; source_done <= 0; write_finish_seen <= 0; awaiting_commit <= 0; display_committed <= 0;
        desired_slide_right <= 0; frame_ready_toggle <= 0;
        ready_slide_right <= 0; load_slide_right <= 0;
        reload_first_after_scan <= 0;
        sd_init_done_o <= 0; scan_done_o <= 0; image_count <= 0; error_code <= 0;
        init_timer <= 0; load_timer <= 0; auto_timer <= 0; recovery_timer <= 0; scan_timer <= 0;
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
            image_count <= 0;
            desired_image <= 0;
            desired_slide_right <= 0;
            image_sector0 <= 0; image_sector1 <= 0; image_sector2 <= 0; image_sector3 <= 0;
            image_width0 <= 0; image_width1 <= 0; image_width2 <= 0; image_width3 <= 0;
            image_height0 <= 0; image_height1 <= 0; image_height2 <= 0; image_height3 <= 0;
        end

        if (scan_kicked && !scan_done && error_code == 0) begin
            if (scan_timer < SCAN_TIMEOUT_CYCLES) scan_timer <= scan_timer + 1'b1;
            else begin op_abort <= 1; error_code <= 3'd3; end
        end else scan_timer <= 0;

        if (scan_found_valid) begin
            case (image_count)
                0: begin image_sector0 <= scan_found_sector; image_width0 <= scan_found_width; image_height0 <= scan_found_height; end
                1: begin image_sector1 <= scan_found_sector; image_width1 <= scan_found_width; image_height1 <= scan_found_height; end
                2: begin image_sector2 <= scan_found_sector; image_width2 <= scan_found_width; image_height2 <= scan_found_height; end
                3: begin image_sector3 <= scan_found_sector; image_width3 <= scan_found_width; image_height3 <= scan_found_height; end
                default: ;
            endcase
            if (image_count < 4) image_count <= image_count + 1;
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
    .scan_start(scan_start_pulse), .scan_start_sector(SCAN_START_SECTOR),
    .scan_max_sector(SCAN_MAX_SECTOR), .scan_target_count(SCAN_TARGET_COUNT),
    .scan_done(scan_done), .scan_found_valid(scan_found_valid),
    .scan_found_sector(scan_found_sector), .scan_found_total(scan_found_total),
    .scan_found_width(scan_found_width), .scan_found_height(scan_found_height),
    .load_start(load_start_pulse), .load_sector(load_sector),
    .sd_init_done(sd_init_done), .state_code(state_code), .bmp_width(bmp_width), .bmp_height(bmp_height),
    .write_req(write_req), .write_req_ack(write_req_ack),
    .sd_sec_read(sd_sec_read), .sd_sec_read_addr(sd_sec_read_addr),
    .sd_sec_read_data(sd_sec_read_data), .sd_sec_read_data_valid(sd_sec_read_data_valid),
    .sd_sec_read_end(sd_sec_read_end), .bmp_data_wr_en(bmp_data_wr_en), .bmp_data(bmp_data)
);

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
