module reference_audio_stream(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [31:0] start_sector,
    input  wire [31:0] data_bytes,
    input  wire [13:0] fifo_wrusedw,
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
            // One sector adds 128 frames; the 8192-frame FIFO has ample
            // headroom when refilling at 4096 or fewer frames.
            if (!sd_sec_read && (fifo_wrusedw <= 14'd4096) && (data_bytes != 0)) begin
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
