module bmp_read(
    input                       clk,
    input                       rst,
    input                       op_abort,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input                       scan_stop,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [2:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [2:0]            scan_found_total,
    output reg [15:0]           scan_found_width,
    output reg [15:0]           scan_found_height,
    output reg                  audio_found_valid,
    output reg [31:0]           audio_found_sector,
    output reg [31:0]           audio_found_bytes,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);

localparam ST_IDLE      = 3'd0;
localparam ST_SCAN      = 3'd1;
localparam ST_LOAD_HDR  = 3'd2;
localparam ST_LOAD_WAIT = 3'd3;
localparam ST_LOAD_DATA = 3'd4;
localparam ST_CHECK     = 3'd5;

reg [2:0]  state;
reg [9:0]  rd_cnt;

reg [7:0]  header_0;
reg [7:0]  header_1;
reg [31:0] dib_header_size;
reg [31:0] file_len;
reg [31:0] pixel_offset;
reg [31:0] width;
reg [31:0] height;
reg [15:0] planes;
reg [15:0] bit_count;
reg [31:0] compression;
reg [63:0] audio_magic;
reg [31:0] audio_data_len;
reg [31:0] audio_sample_rate;
reg [15:0] audio_bits;
reg [15:0] audio_channels;

reg [31:0] scan_sector;
reg [31:0] load_sector_latched;
reg [31:0] bmp_len_cnt;
reg [1:0]  bmp_byte_idx;
reg [15:0] row_byte_cnt;
reg [15:0] src_x;
reg [15:0] src_y;
reg [31:0] x_acc;
reg [31:0] y_acc;
reg        row_selected;
reg [15:0] row_payload_latched;
reg [15:0] row_stride_latched;
reg        header_basic_ok_latched;
reg        header_geometry_ok_latched;
reg        check_from_load;
reg [31:0] file_sector_count_latched;
reg        audio_header_ok_latched;
reg [31:0] audio_data_len_latched;
reg        audio_found_once;

wire header_basic_ok;
wire header_geometry_ok;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_miss;
wire audio_header_ok;
wire vga_source = (width == 32'd640) && (height == 32'd480);

assign ready = (state == ST_IDLE);
assign header_basic_ok = (header_0 == "B") &&
                         (header_1 == "M") &&
                         (dib_header_size >= 32'd40) &&
                         (planes        == 16'd1) &&
                         (pixel_offset  >= 32'd54) &&
                         (file_len      >  pixel_offset) &&
                         (file_len      <= 32'd8_388_608);
assign header_geometry_ok = (width[31:16]  == 16'd0) &&
                      (height[31:16] == 16'd0) &&
                      (((width[15:0] == 16'd640) &&
                        (height[15:0] == 16'd480)) ||
                       ((width[15:0] >= bmp_width) &&
                        (height[15:0] >= bmp_height))) &&
                      (width[15:0]   <= 16'd1920) &&
                      (height[15:0]  <= 16'd1080) &&
                      (bit_count    == 16'd24) &&
                      (compression  == 32'd0);
assign bmp_data_valid = (sd_sec_read_data_valid == 1'b1) &&
                        (bmp_len_cnt >= pixel_offset) &&
                        (bmp_len_cnt <  file_len);
assign file_sector_count = (file_len == 32'd0) ? 32'd1 : ((file_len + 32'd511) >> 9);
assign next_scan_sector_if_miss  = scan_sector + 32'd1;
// BGM.AUD begins with one aligned metadata sector. Byte zero is kept in the
// low byte of audio_magic, so this constant spells "SXAUD001" in file order.
assign audio_header_ok = (audio_magic       == 64'h3130304455415853) &&
                         (audio_data_len    >= 32'd4) &&
                         (audio_data_len[1:0] == 2'b00) &&
                         (audio_sample_rate == 32'd48000) &&
                         (audio_bits        == 16'd16) &&
                         (audio_channels    == 16'd2);

always @(posedge clk or posedge rst) begin
    if (rst || op_abort) begin
        row_payload_latched <= 16'd0;
        row_stride_latched <= 16'd0;
    end else if ((state == ST_LOAD_HDR) && sd_sec_read_end) begin
        row_payload_latched <= (width[15:0] << 1) + width[15:0];
        row_stride_latched <= (((width[15:0] << 1) + width[15:0] + 16'd3) & 16'hfffc);
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rd_cnt <= 10'd0;
    end else if (op_abort) begin
        rd_cnt <= 10'd0;
    end else if ((state == ST_SCAN) || (state == ST_LOAD_HDR)) begin
        if (sd_sec_read_data_valid)
            rd_cnt <= rd_cnt + 10'd1;
        else if (sd_sec_read_end)
            rd_cnt <= 10'd0;
    end else begin
        rd_cnt <= 10'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        dib_header_size <= 32'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        planes       <= 16'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
    end else if (op_abort) begin
        header_0     <= 8'd0;
        header_1     <= 8'd0;
        dib_header_size <= 32'd0;
        file_len     <= 32'd0;
        pixel_offset <= 32'd54;
        width        <= 32'd0;
        height       <= 32'd0;
        planes       <= 16'd0;
        bit_count    <= 16'd0;
        compression  <= 32'd0;
    end else if (((state == ST_SCAN) || (state == ST_LOAD_HDR)) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : header_0 <= sd_sec_read_data;
            10'd1 : header_1 <= sd_sec_read_data;

            10'd2 : file_len[7:0] <= sd_sec_read_data;
            10'd3 : file_len[15:8] <= sd_sec_read_data;
            10'd4 : file_len[23:16] <= sd_sec_read_data;
            10'd5 : file_len[31:24] <= sd_sec_read_data;

            10'd10: pixel_offset[7:0] <= sd_sec_read_data;
            10'd11: pixel_offset[15:8] <= sd_sec_read_data;
            10'd12: pixel_offset[23:16] <= sd_sec_read_data;
            10'd13: pixel_offset[31:24] <= sd_sec_read_data;

            10'd14: dib_header_size[7:0] <= sd_sec_read_data;
            10'd15: dib_header_size[15:8] <= sd_sec_read_data;
            10'd16: dib_header_size[23:16] <= sd_sec_read_data;
            10'd17: dib_header_size[31:24] <= sd_sec_read_data;

            10'd18: width[7:0] <= sd_sec_read_data;
            10'd19: width[15:8] <= sd_sec_read_data;
            10'd20: width[23:16] <= sd_sec_read_data;
            10'd21: width[31:24] <= sd_sec_read_data;

            10'd22: height[7:0] <= sd_sec_read_data;
            10'd23: height[15:8] <= sd_sec_read_data;
            10'd24: height[23:16] <= sd_sec_read_data;
            10'd25: height[31:24] <= sd_sec_read_data;

            10'd26: planes[7:0] <= sd_sec_read_data;
            10'd27: planes[15:8] <= sd_sec_read_data;

            10'd28: bit_count[7:0] <= sd_sec_read_data;
            10'd29: bit_count[15:8] <= sd_sec_read_data;

            10'd30: compression[7:0] <= sd_sec_read_data;
            10'd31: compression[15:8] <= sd_sec_read_data;
            10'd32: compression[23:16] <= sd_sec_read_data;
            10'd33: compression[31:24] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

// Capture the compact audio metadata independently of the BMP header fields.
always @(posedge clk or posedge rst) begin
    if (rst || op_abort) begin
        audio_magic <= 64'd0;
        audio_data_len <= 32'd0;
        audio_sample_rate <= 32'd0;
        audio_bits <= 16'd0;
        audio_channels <= 16'd0;
    end else if ((state == ST_SCAN) && sd_sec_read_data_valid) begin
        case (rd_cnt)
            10'd0 : audio_magic[7:0] <= sd_sec_read_data;
            10'd1 : audio_magic[15:8] <= sd_sec_read_data;
            10'd2 : audio_magic[23:16] <= sd_sec_read_data;
            10'd3 : audio_magic[31:24] <= sd_sec_read_data;
            10'd4 : audio_magic[39:32] <= sd_sec_read_data;
            10'd5 : audio_magic[47:40] <= sd_sec_read_data;
            10'd6 : audio_magic[55:48] <= sd_sec_read_data;
            10'd7 : audio_magic[63:56] <= sd_sec_read_data;
            10'd8 : audio_data_len[7:0] <= sd_sec_read_data;
            10'd9 : audio_data_len[15:8] <= sd_sec_read_data;
            10'd10: audio_data_len[23:16] <= sd_sec_read_data;
            10'd11: audio_data_len[31:24] <= sd_sec_read_data;
            10'd12: audio_sample_rate[7:0] <= sd_sec_read_data;
            10'd13: audio_sample_rate[15:8] <= sd_sec_read_data;
            10'd14: audio_sample_rate[23:16] <= sd_sec_read_data;
            10'd15: audio_sample_rate[31:24] <= sd_sec_read_data;
            10'd16: audio_bits[7:0] <= sd_sec_read_data;
            10'd17: audio_bits[15:8] <= sd_sec_read_data;
            10'd18: audio_channels[7:0] <= sd_sec_read_data;
            10'd19: audio_channels[15:8] <= sd_sec_read_data;
            default: ;
        endcase
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_len_cnt <= 32'd0;
    end else if (op_abort) begin
        bmp_len_cnt <= 32'd0;
    end else if (state == ST_LOAD_DATA) begin
        if (sd_sec_read_data_valid)
            bmp_len_cnt <= bmp_len_cnt + 32'd1;
    end else begin
        bmp_len_cnt <= 32'd0;
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
        bmp_byte_idx    <= 2'd0;
        row_byte_cnt    <= 16'd0;
        src_x           <= 16'd0;
        src_y           <= 16'd0;
        x_acc           <= 32'd0;
        y_acc           <= 32'd0;
        row_selected    <= 1'b0;
    end else if (op_abort) begin
        bmp_data_wr_en <= 1'b0;
        bmp_data       <= 24'd0;
        bmp_byte_idx    <= 2'd0;
        row_byte_cnt    <= 16'd0;
        src_x           <= 16'd0;
        src_y           <= 16'd0;
        x_acc           <= 32'd0;
        y_acc           <= 32'd0;
        row_selected    <= 1'b0;
    end else if (state == ST_LOAD_DATA) begin
        bmp_data_wr_en <= 1'b0;
        if (bmp_data_valid) begin
            // BMP rows are padded to a 4-byte boundary.  Padding bytes must
            // not participate in B/G/R assembly.
            if ((row_byte_cnt < row_payload_latched) && (src_y < height[15:0])) begin
                case (bmp_byte_idx)
                    2'd0: begin
                        bmp_data[7:0] <= sd_sec_read_data;
                        bmp_byte_idx   <= 2'd1;
                    end
                    2'd1: begin
                        bmp_data[15:8] <= sd_sec_read_data;
                        bmp_byte_idx    <= 2'd2;
                    end
                    2'd2: begin
                        bmp_data[23:16] <= sd_sec_read_data;
                        bmp_byte_idx     <= 2'd0;

                        // Lightweight nearest-neighbour down-scaler.  It
                        // emits exactly 640 pixels on each of 480 selected
                        // source rows without a divider in the pixel path.
                        if (vga_source)
                            bmp_data_wr_en <= 1'b1;
                        else if (row_selected) begin
                            if ((x_acc + bmp_width) >= width) begin
                                bmp_data_wr_en <= 1'b1;
                                x_acc <= x_acc + bmp_width - width;
                            end else begin
                                x_acc <= x_acc + bmp_width;
                            end
                        end

                        if (src_x + 16'd1 >= width[15:0])
                            src_x <= 16'd0;
                        else
                            src_x <= src_x + 16'd1;
                    end
                    default: bmp_byte_idx <= 2'd0;
                endcase
            end

            if ((row_byte_cnt + 16'd1) >= row_stride_latched) begin
                row_byte_cnt <= 16'd0;
                bmp_byte_idx <= 2'd0;
                src_x        <= 16'd0;
                x_acc        <= vga_source ? 32'd0 : (width - bmp_width);

                if (src_y + 16'd1 < height[15:0]) begin
                    src_y <= src_y + 16'd1;
                    if (vga_source) begin
                        row_selected <= 1'b1;
                        y_acc <= 32'd0;
                    end else if ((y_acc + bmp_height) >= height) begin
                        row_selected <= 1'b1;
                        y_acc <= y_acc + bmp_height - height;
                    end else begin
                        row_selected <= 1'b0;
                        y_acc <= y_acc + bmp_height;
                    end
                end else begin
                    src_y        <= src_y;
                    row_selected <= 1'b0;
                end
            end else begin
                row_byte_cnt <= row_byte_cnt + 16'd1;
            end
        end
    end else begin
        bmp_data_wr_en <= 1'b0;
        bmp_byte_idx    <= 2'd0;
        row_byte_cnt    <= 16'd0;
        src_x           <= 16'd0;
        src_y           <= 16'd0;
        x_acc           <= (width >= bmp_width) ? (width - bmp_width) : 32'd0;
        if (vga_source) begin
            y_acc        <= 32'd0;
            row_selected <= 1'b1;
        end else if (bmp_height >= height) begin
            y_acc        <= bmp_height - height;
            row_selected <= 1'b1;
        end else begin
            y_acc        <= bmp_height;
            row_selected <= 1'b0;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_found_width  <= 16'd0;
        scan_found_height <= 16'd0;
        audio_found_valid <= 1'b0;
        audio_found_sector <= 32'd0;
        audio_found_bytes <= 32'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        header_basic_ok_latched <= 1'b0;
        header_geometry_ok_latched <= 1'b0;
        check_from_load <= 1'b0;
        file_sector_count_latched <= 32'd1;
        audio_header_ok_latched <= 1'b0;
        audio_data_len_latched <= 32'd0;
        audio_found_once <= 1'b0;
    end else if (!sd_init_done || op_abort) begin
        state             <= ST_IDLE;
        state_code        <= 4'd0;
        sd_sec_read       <= 1'b0;
        sd_sec_read_addr  <= 32'd0;
        write_req         <= 1'b0;
        scan_done         <= 1'b0;
        scan_found_valid  <= 1'b0;
        scan_found_sector <= 32'd0;
        scan_found_total  <= 3'd0;
        scan_found_width  <= 16'd0;
        scan_found_height <= 16'd0;
        audio_found_valid <= 1'b0;
        audio_found_sector <= 32'd0;
        audio_found_bytes <= 32'd0;
        scan_sector       <= 32'd0;
        load_sector_latched <= 32'd0;
        header_basic_ok_latched <= 1'b0;
        header_geometry_ok_latched <= 1'b0;
        check_from_load <= 1'b0;
        file_sector_count_latched <= 32'd1;
        audio_header_ok_latched <= 1'b0;
        audio_data_len_latched <= 32'd0;
        audio_found_once <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        audio_found_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    audio_found_once <= 1'b0;
                    scan_sector      <= scan_start_sector;
                    sd_sec_read_addr <= scan_start_sector;
                    state            <= ST_SCAN;
                end else if (load_start) begin
                    load_sector_latched <= load_sector;
                    sd_sec_read_addr    <= load_sector;
                    state               <= ST_LOAD_HDR;
                end
            end

            ST_SCAN: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    header_basic_ok_latched <= header_basic_ok;
                    header_geometry_ok_latched <= header_geometry_ok;
                    file_sector_count_latched <= file_sector_count;
                    audio_header_ok_latched <= audio_header_ok;
                    audio_data_len_latched <= audio_data_len;
                    check_from_load <= 1'b0;
                    state <= ST_CHECK;
                end
            end

            ST_CHECK: begin
                state_code <= 4'd2;
                if (check_from_load) begin
                    if (header_basic_ok_latched && header_geometry_ok_latched) begin
                        write_req        <= 1'b1;
                        sd_sec_read_addr <= load_sector_latched;
                        state            <= ST_LOAD_WAIT;
                    end else begin
                        state <= ST_IDLE;
                    end
                end else if (scan_stop) begin
                    // Finish only between sector reads.  This keeps the SD
                    // controller transaction intact and lets the caller use
                    // every valid image already found instead of aborting and
                    // reinitializing the card.
                    scan_done   <= 1'b1;
                    state       <= ST_IDLE;
                    sd_sec_read <= 1'b0;
                end else begin
                    if (audio_header_ok_latched) begin
                        if (!audio_found_once) begin
                            audio_found_valid  <= 1'b1;
                            audio_found_sector <= scan_sector + 32'd1;
                            audio_found_bytes  <= audio_data_len_latched;
                            audio_found_once   <= 1'b1;
                        end

                        // Skip the aligned metadata sector and the complete
                        // PCM payload instead of scanning 96k audio sectors.
                        if ((scan_found_total >= scan_target_count) ||
                            ((scan_sector + 32'd1 + ((audio_data_len_latched + 32'd511) >> 9)) > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= scan_sector + 32'd1 + ((audio_data_len_latched + 32'd511) >> 9);
                            scan_sector      <= scan_sector + 32'd1 + ((audio_data_len_latched + 32'd511) >> 9);
                        end else begin
                            sd_sec_read_addr <= scan_sector + 32'd1 + ((audio_data_len_latched + 32'd511) >> 9);
                            scan_sector      <= scan_sector + 32'd1 + ((audio_data_len_latched + 32'd511) >> 9);
                            state            <= ST_SCAN;
                        end
                    end else if (header_basic_ok_latched && header_geometry_ok_latched) begin
                        scan_found_valid  <= 1'b1;
                        scan_found_sector <= scan_sector;
                        scan_found_total  <= scan_found_total + 3'd1;
                        scan_found_width  <= width[15:0];
                        scan_found_height <= height[15:0];

                        if (((scan_found_total + 3'd1 >= scan_target_count) && audio_found_once) ||
                            ((scan_sector + file_sector_count_latched) > scan_max_sector)) begin
                            scan_done        <= 1'b1;
                            state            <= ST_IDLE;
                            sd_sec_read_addr <= scan_sector + file_sector_count_latched;
                            scan_sector      <= scan_sector + file_sector_count_latched;
                        end else begin
                            sd_sec_read_addr <= scan_sector + file_sector_count_latched;
                            scan_sector      <= scan_sector + file_sector_count_latched;
                            state            <= ST_SCAN;
                        end
                    end else begin
                        if (scan_sector >= scan_max_sector) begin
                            scan_done <= 1'b1;
                            state     <= ST_IDLE;
                        end else begin
                            sd_sec_read_addr <= next_scan_sector_if_miss;
                            scan_sector      <= next_scan_sector_if_miss;
                            state            <= ST_SCAN;
                        end
                    end
                end
            end

            ST_LOAD_HDR: begin
                state_code  <= 4'd2;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    header_basic_ok_latched <= header_basic_ok;
                    header_geometry_ok_latched <= header_geometry_ok;
                    file_sector_count_latched <= file_sector_count;
                    check_from_load <= 1'b1;
                    state <= ST_CHECK;
                end
            end

            ST_LOAD_WAIT: begin
                state_code <= 4'd3;
                if (write_req_ack) begin
                    write_req <= 1'b0;
                    state     <= ST_LOAD_DATA;
                end
            end

            ST_LOAD_DATA: begin
                state_code  <= 4'd4;
                sd_sec_read <= 1'b1;

                if (sd_sec_read_end) begin
                    sd_sec_read <= 1'b0;
                    if (bmp_len_cnt >= file_len) begin
                        state <= ST_IDLE;
                    end else begin
                        sd_sec_read_addr <= sd_sec_read_addr + 32'd1;
                    end
                end
            end

            default: begin
                state       <= ST_IDLE;
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;
            end
        endcase
    end
end

endmodule
