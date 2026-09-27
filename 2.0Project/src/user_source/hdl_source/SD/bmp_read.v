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
    output reg                  scan_found_sprint,
    output reg                  audio_found_valid,
    output reg [2:0]            audio_found_index,
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

    output                      bmp_data_wr_en,
    output [23:0]               bmp_data
);

localparam ST_IDLE      = 3'd0;
// SDRAM request acknowledgement originates in mem_clk, not this SD clock.
reg write_ack_meta, write_ack_sync;
always @(posedge clk or posedge rst) begin
    if (rst) begin write_ack_meta <= 1'b0; write_ack_sync <= 1'b0; end
    else begin write_ack_meta <= write_req_ack; write_ack_sync <= write_ack_meta; end
end
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
reg [31:0] x_pixels_per_metre, y_pixels_per_metre;
wire sprint_background_tag = (x_pixels_per_metre == 32'd12345) &&
                             (y_pixels_per_metre == 32'd54321);
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
reg [2:0]  audio_found_count;
reg        sprint_tag_latched;

wire header_basic_ok;
wire header_geometry_ok;
wire bmp_data_valid;
wire [31:0] file_sector_count;
wire [31:0] next_scan_sector_if_miss;
wire audio_header_ok;
wire vga_source = (width == 32'd640) && (height == 32'd480);

reg raw_pixel_valid;
reg [23:0] raw_pixel;
wire scaler_busy, scaler_fault;
reg write_req_previous;
always @(posedge clk or posedge rst) begin
    if (rst) write_req_previous <= 1'b0;
    else write_req_previous <= write_req;
end
saixian_load_scaler u_scaler(
    .clk(clk), .rst(rst | op_abort), .start(write_req && !write_req_previous),
    .source_width(width[15:0]), .source_height(height[15:0]),
    .pixel_valid(raw_pixel_valid), .pixel_in(raw_pixel),
    .pixel_out_valid(bmp_data_wr_en), .pixel_out(bmp_data),
    .busy(scaler_busy), .fault(scaler_fault));
assign ready = (state == ST_IDLE) && !scaler_busy;
assign header_basic_ok = (header_0 == "B") &&
                         (header_1 == "M") &&
                         (dib_header_size >= 32'd40) &&
                         (planes        == 16'd1) &&
                         (pixel_offset  >= 32'd54) &&
                         (file_len      >  pixel_offset) &&
                         (file_len      <= 32'd8_388_608);
assign header_geometry_ok = (width[31:16]  == 16'd0) &&
                      (height[31:16] == 16'd0) &&
                      (width[15:0] >= 16'd640) &&
                      (height[15:0] >= 16'd360) &&
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
        x_pixels_per_metre <= 32'd0;
        y_pixels_per_metre <= 32'd0;
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
        x_pixels_per_metre <= 32'd0;
        y_pixels_per_metre <= 32'd0;
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
            10'd38: x_pixels_per_metre[7:0] <= sd_sec_read_data;
            10'd39: x_pixels_per_metre[15:8] <= sd_sec_read_data;
            10'd40: x_pixels_per_metre[23:16] <= sd_sec_read_data;
            10'd41: x_pixels_per_metre[31:24] <= sd_sec_read_data;
            10'd42: y_pixels_per_metre[7:0] <= sd_sec_read_data;
            10'd43: y_pixels_per_metre[15:8] <= sd_sec_read_data;
            10'd44: y_pixels_per_metre[23:16] <= sd_sec_read_data;
            10'd45: y_pixels_per_metre[31:24] <= sd_sec_read_data;
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
        raw_pixel_valid <= 1'b0;
        raw_pixel       <= 24'd0;
        bmp_byte_idx    <= 2'd0;
        row_byte_cnt    <= 16'd0;
        src_x           <= 16'd0;
        src_y           <= 16'd0;
        x_acc           <= 32'd0;
        y_acc           <= 32'd0;
        row_selected    <= 1'b0;
    end else if (op_abort) begin
        raw_pixel_valid <= 1'b0;
        raw_pixel       <= 24'd0;
        bmp_byte_idx    <= 2'd0;
        row_byte_cnt    <= 16'd0;
        src_x           <= 16'd0;
        src_y           <= 16'd0;
        x_acc           <= 32'd0;
        y_acc           <= 32'd0;
        row_selected    <= 1'b0;
    end else if (state == ST_LOAD_DATA) begin
        raw_pixel_valid <= 1'b0;
        if (bmp_data_valid) begin
            // BMP rows are padded to a 4-byte boundary.  Padding bytes must
            // not participate in B/G/R assembly.
            if ((row_byte_cnt < row_payload_latched) && (src_y < height[15:0])) begin
                case (bmp_byte_idx)
                    2'd0: begin
                        raw_pixel[7:0] <= sd_sec_read_data;
                        bmp_byte_idx   <= 2'd1;
                    end
                    2'd1: begin
                        raw_pixel[15:8] <= sd_sec_read_data;
                        bmp_byte_idx    <= 2'd2;
                    end
                    2'd2: begin
                        raw_pixel[23:16] <= sd_sec_read_data;
                        bmp_byte_idx     <= 2'd0;

                        // Decode every source pixel. The separable fixed-point
                        // scaler generates a native 1280x720 framebuffer.
                        raw_pixel_valid <= 1'b1;

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
        raw_pixel_valid <= 1'b0;
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
        scan_found_sprint <= 1'b0;
        audio_found_valid <= 1'b0;
        audio_found_index <= 3'd0;
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
        audio_found_count <= 3'd0;
        sprint_tag_latched <= 1'b0;
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
        scan_found_sprint <= 1'b0;
        audio_found_valid <= 1'b0;
        audio_found_index <= 3'd0;
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
        audio_found_count <= 3'd0;
        sprint_tag_latched <= 1'b0;
    end else begin
        scan_found_valid <= 1'b0;
        scan_found_sprint <= 1'b0;
        audio_found_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                state_code  <= 4'd1;
                sd_sec_read <= 1'b0;
                write_req   <= 1'b0;

                if (scan_start) begin
                    scan_done        <= 1'b0;
                    scan_found_total <= 3'd0;
                    audio_found_count <= 3'd0;
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
                    sprint_tag_latched <= sprint_background_tag;
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
                        if (audio_found_count < 3'd5) begin
                            audio_found_valid  <= 1'b1;
                            audio_found_index  <= audio_found_count;
                            audio_found_sector <= scan_sector + 32'd1;
                            audio_found_bytes  <= audio_data_len_latched;
                            audio_found_count  <= audio_found_count + 1'b1;
                        end

                        // Skip the aligned metadata sector and the complete
                        // PCM payload instead of scanning 96k audio sectors.
                        if (((scan_found_total >= scan_target_count) && (audio_found_count >= 3'd4)) ||
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
                        scan_found_sprint <= sprint_tag_latched;

                        if (((scan_found_total + 3'd1 >= scan_target_count) && (audio_found_count >= 3'd5)) ||
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
                if (write_ack_sync) begin
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

// BMP-load-domain separable bilinear resampler. SPI input pixels are sparse;
// no full-frame intermediate store is needed. Three banked lines prevent the
// next source row overwriting either row used by vertical interpolation.
// Endpoints are aligned, position is Q11.16 and interpolation weight is Q0.8.
module saixian_load_scaler #(
    parameter integer OUT_WIDTH=1280, OUT_HEIGHT=720,
    parameter integer VERTICAL_PERIOD=16
)(
    input wire clk, rst, start,
    input wire [15:0] source_width, source_height,
    input wire pixel_valid, input wire [23:0] pixel_in,
    output reg pixel_out_valid, output reg [23:0] pixel_out,
    output wire busy, output reg fault
);
localparam integer CHUNKS=(OUT_WIDTH+511)/512;
reg active, native_size;
reg [3:0] vertical_pace;
reg [10:0] in_x, in_y, source_last_x, source_last_y;
reg [16:0] x_step, y_step;
reg [26:0] xpos, ypos;
reg [26:0] x_dividend,y_dividend,x_quotient,y_quotient;
reg [11:0] x_remainder,y_remainder;
reg [4:0] divide_count;
reg dividing;
wire [11:0] x_trial={x_remainder[10:0],x_dividend[26]};
wire [11:0] y_trial={y_remainder[10:0],y_dividend[26]};
wire x_div_bit=(x_trial>=OUT_WIDTH-1);
wire y_div_bit=(y_trial>=OUT_HEIGHT-1);
reg [10:0] hx, vx;
reg [9:0] vy;
reg [1:0] write_bank, h_bank, v_bank;
reg h_run, v_run;
wire vertical_step=v_run && vertical_pace==0;
reg [10:0] sample_x, sample_y, v_source_y;
reg [23:0] left_pixel, current_pixel, previous_pixel;
reg h_valid, h_last;
reg h_calc_valid, h_calc_last;
reg [10:0] h_calc_addr,h_calc_row;
reg [1:0] h_calc_bank;
reg [23:0] h_calc_base;
reg [7:0] h_calc_weight;
reg signed [8:0] hd_r,hd_g,hd_b;
reg [10:0] h_addr;
reg [1:0] h_bank_q;
reg [10:0] h_row_q;
reg [23:0] h_base;
reg signed [17:0] hp_r, hp_g, hp_b;
wire [26:0] h_position=(hx==OUT_WIDTH-1) ? {source_last_x,16'd0} : xpos;
// ceil(position)<=index iff floor(position)<index, or equal with zero
// fraction. Equivalent comparison avoids a wide increment/carry chain.
wire h_available=(h_position[26:16]<sample_x) ||
                 (h_position[26:16]==sample_x && h_position[15:0]==0);
wire [7:0] h_weight=h_position[15:8];
wire [23:0] h_left=(sample_x==0 || h_position[15:0]==0) ? current_pixel : left_pixel;
function [7:0] clamp;
    input signed [18:0] n;
    begin clamp=(n<0) ? 0 : ((n>255) ? 255 : n[7:0]); end
endfunction
wire [7:0] hr=clamp($signed({1'b0,h_base[23:16]})+(hp_r>>>8));
wire [7:0] hg=clamp($signed({1'b0,h_base[15:8]})+(hp_g>>>8));
wire [7:0] hb=clamp($signed({1'b0,h_base[7:0]})+(hp_b>>>8));
wire [15:0] h_word={hr[7:3],hg[7:2],hb[7:3]};
reg [1:0] read_chunk, read_bank;
wire [15:0] bank_read [0:2];
genvar bank,chunk;
generate for(bank=0;bank<3;bank=bank+1) begin: banks
    wire [15:0] q [0:CHUNKS-1];
    for(chunk=0;chunk<CHUNKS;chunk=chunk+1) begin: chunks
        reg [15:0] memory [0:511]; /* fehdl force_ram=1, ram_style="bram" */
        reg [15:0] qr;
        always @(posedge clk) begin
            if(h_valid && h_bank_q==bank && (h_addr>>9)==chunk)
                memory[h_addr[8:0]] <= h_word;
            if(v_run && (vx>>9)==chunk) qr<=memory[vx[8:0]];
        end
        assign q[chunk]=qr;
    end
    reg [15:0] selected;
    integer k;
    always @* begin
        selected=0;
        for(k=0;k<CHUNKS;k=k+1) if(read_chunk==k) selected=q[k];
    end
    assign bank_read[bank]=selected;
end endgenerate
reg read_first, read_valid, read_last;
reg [7:0] read_weight;
reg mix_valid, mix_last;
reg select_valid, select_last;
reg [23:0] selected_current, selected_previous;
reg [7:0] selected_weight;
reg [23:0] mix_base;
reg signed [17:0] vp_r, vp_g, vp_b;
reg [15:0] current_word, previous_word;
reg [23:0] current_rgb, previous_rgb;
always @* begin
    case(read_bank)
        0:begin current_word=bank_read[0];previous_word=bank_read[2];end
        1:begin current_word=bank_read[1];previous_word=bank_read[0];end
        default:begin current_word=bank_read[2];previous_word=bank_read[1];end
    endcase
    if(read_first || read_weight==0) previous_word=current_word;
    current_rgb={current_word[15:11],current_word[15:13],current_word[10:5],current_word[10:9],current_word[4:0],current_word[4:2]};
    previous_rgb={previous_word[15:11],previous_word[15:13],previous_word[10:5],previous_word[10:9],previous_word[4:0],previous_word[4:2]};
end
wire [26:0] next_ypos=(vy==OUT_HEIGHT-2) ? {source_last_y,16'd0} : ypos+y_step;
wire next_y_available=(next_ypos[26:16]<v_source_y) ||
                      (next_ypos[26:16]==v_source_y && next_ypos[15:0]==0);
assign busy=active;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        active<=0;native_size<=0;fault<=0;pixel_out_valid<=0;pixel_out<=0;vertical_pace<=0;
        in_x<=0;in_y<=0;source_last_x<=0;source_last_y<=0;x_step<=0;y_step<=0;xpos<=0;ypos<=0;
        x_dividend<=0;y_dividend<=0;x_quotient<=0;y_quotient<=0;
        x_remainder<=0;y_remainder<=0;divide_count<=0;dividing<=0;
        hx<=0;vx<=0;vy<=0;write_bank<=0;h_bank<=0;v_bank<=0;h_run<=0;v_run<=0;
        sample_x<=0;sample_y<=0;v_source_y<=0;left_pixel<=0;current_pixel<=0;previous_pixel<=0;
        h_valid<=0;h_last<=0;h_addr<=0;h_bank_q<=0;h_row_q<=0;h_base<=0;hp_r<=0;hp_g<=0;hp_b<=0;
        h_calc_valid<=0;h_calc_last<=0;h_calc_addr<=0;h_calc_row<=0;h_calc_bank<=0;
        h_calc_base<=0;h_calc_weight<=0;hd_r<=0;hd_g<=0;hd_b<=0;
        read_chunk<=0;read_bank<=0;read_first<=0;read_valid<=0;read_last<=0;read_weight<=0;
        mix_valid<=0;mix_last<=0;mix_base<=0;vp_r<=0;vp_g<=0;vp_b<=0;
        select_valid<=0;select_last<=0;selected_current<=0;selected_previous<=0;selected_weight<=0;
    end else if(start) begin
        active<=1;fault<=0;native_size<=(source_width==OUT_WIDTH && source_height==OUT_HEIGHT);vertical_pace<=0;
        // Compute terminal indices once, rather than subtracting in every
        // endpoint/ceil comparison on the 100MHz pixel-enable path.
        source_last_x<=source_width[10:0]-11'd1;source_last_y<=source_height[10:0]-11'd1;
        // Once per image: 27-cycle restoring division, not a huge
        // combinational divider in the 100MHz source-pixel path.
        x_dividend<={source_width[10:0]-11'd1,16'd0};
        y_dividend<={source_height[10:0]-11'd1,16'd0};
        x_quotient<=0;y_quotient<=0;x_remainder<=0;y_remainder<=0;
        divide_count<=0;dividing<=1;
        in_x<=0;in_y<=0;hx<=0;vx<=0;vy<=0;xpos<=0;ypos<=0;write_bank<=0;
        h_run<=0;v_run<=0;h_valid<=0;h_calc_valid<=0;read_valid<=0;select_valid<=0;mix_valid<=0;pixel_out_valid<=0;
    end else begin
        pixel_out_valid<=0;h_calc_valid<=0;h_valid<=h_calc_valid;read_valid<=vertical_step;select_valid<=read_valid;mix_valid<=select_valid;
        // Limit the vertical line burst to 6.25 Mpixel/s at 100 MHz.
        // Without pacing, packed writes can reach 50 Mword/s and compete
        // with the 75 MHz video consumer on the 50 MHz SDRAM interface.
        if(!v_run || vertical_pace==VERTICAL_PERIOD-1) vertical_pace<=0;
        else vertical_pace<=vertical_pace+1'b1;
        if(h_calc_valid) begin
            h_addr<=h_calc_addr;h_bank_q<=h_calc_bank;h_row_q<=h_calc_row;h_last<=h_calc_last;
            h_base<=h_calc_base;
            hp_r<=hd_r*$signed({1'b0,h_calc_weight});
            hp_g<=hd_g*$signed({1'b0,h_calc_weight});
            hp_b<=hd_b*$signed({1'b0,h_calc_weight});
        end
        if(dividing) begin
            x_dividend<={x_dividend[25:0],1'b0};y_dividend<={y_dividend[25:0],1'b0};
            x_quotient<={x_quotient[25:0],x_div_bit};y_quotient<={y_quotient[25:0],y_div_bit};
            x_remainder<=x_div_bit ? x_trial-(OUT_WIDTH-1) : x_trial;
            y_remainder<=y_div_bit ? y_trial-(OUT_HEIGHT-1) : y_trial;
            if(divide_count==26) begin
                x_step<={x_quotient[15:0],x_div_bit};y_step<={y_quotient[15:0],y_div_bit};dividing<=0;
            end else divide_count<=divide_count+1'b1;
        end
        if(pixel_valid && active) begin
            if(native_size) begin
                pixel_out_valid<=1;pixel_out<=pixel_in;
                if(in_x==source_last_x && in_y==source_last_y) active<=0;
            end else begin
                if(h_run || dividing) begin fault<=1;active<=0;end
                current_pixel<=pixel_in;
                left_pixel<=(in_x==0) ? pixel_in : previous_pixel;
                previous_pixel<=pixel_in;sample_x<=in_x;sample_y<=in_y;h_bank<=write_bank;h_run<=1;
            end
            if(in_x==source_last_x) begin
                in_x<=0;in_y<=in_y+1'b1;write_bank<=(write_bank==2) ? 0 : write_bank+1'b1;
            end else in_x<=in_x+1'b1;
        end
        if(h_run) begin
            if(h_available) begin
                h_calc_valid<=1;h_calc_addr<=hx;h_calc_bank<=h_bank;h_calc_row<=sample_y;h_calc_last<=(hx==OUT_WIDTH-1);
                h_calc_base<=h_left;h_calc_weight<=h_weight;
                hd_r<=$signed({1'b0,current_pixel[23:16]})-$signed({1'b0,h_left[23:16]});
                hd_g<=$signed({1'b0,current_pixel[15:8]})-$signed({1'b0,h_left[15:8]});
                hd_b<=$signed({1'b0,current_pixel[7:0]})-$signed({1'b0,h_left[7:0]});
                if(hx==OUT_WIDTH-1) begin hx<=0;xpos<=0;h_run<=0;end
                else begin hx<=hx+1'b1;xpos<=xpos+x_step;end
            end else h_run<=0;
        end
        if(h_valid && h_last) begin
            // Entire horizontally resampled row is now committed in line RAM.
            if(v_run) begin fault<=1;active<=0;end
            else if(ypos[26:16]<h_row_q || (ypos[26:16]==h_row_q && ypos[15:0]==0)) begin
                v_run<=1;v_bank<=h_bank_q;v_source_y<=h_row_q;vx<=0;
            end
        end
        if(vertical_step) begin
            read_chunk<=vx>>9;read_bank<=v_bank;read_first<=(v_source_y==0);
            read_weight<=ypos[15:8];read_last<=(vx==OUT_WIDTH-1 && vy==OUT_HEIGHT-1);
            if(vx==OUT_WIDTH-1) begin
                vx<=0;vy<=vy+1'b1;ypos<=next_ypos;
                if(vy==OUT_HEIGHT-1 || !next_y_available) v_run<=0;
            end else vx<=vx+1'b1;
        end
        if(read_valid) begin
            selected_current<=current_rgb;selected_previous<=previous_rgb;
            selected_weight<=read_weight;select_last<=read_last;
        end
        if(select_valid) begin
            mix_base<=selected_previous;mix_last<=select_last;
            vp_r<=($signed({1'b0,selected_current[23:16]})-$signed({1'b0,selected_previous[23:16]}))*$signed({1'b0,selected_weight});
            vp_g<=($signed({1'b0,selected_current[15:8]})-$signed({1'b0,selected_previous[15:8]}))*$signed({1'b0,selected_weight});
            vp_b<=($signed({1'b0,selected_current[7:0]})-$signed({1'b0,selected_previous[7:0]}))*$signed({1'b0,selected_weight});
        end
        if(mix_valid) begin
            pixel_out_valid<=1;
            pixel_out<={clamp($signed({1'b0,mix_base[23:16]})+(vp_r>>>8)),
                        clamp($signed({1'b0,mix_base[15:8]})+(vp_g>>>8)),
                        clamp($signed({1'b0,mix_base[7:0]})+(vp_b>>>8))};
            if(mix_last) active<=0;
        end
    end
end
endmodule
