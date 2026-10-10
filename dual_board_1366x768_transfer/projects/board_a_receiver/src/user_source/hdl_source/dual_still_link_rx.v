`timescale 1ns/1ps
// Board A adapter: accepts one source-synchronous RGB565 frame, pairs pixels
// into the existing framebuffer writer's 32-bit word format, and validates
// frame length/markers before declaring the image ready for display.
module dual_still_link_rx #(
    parameter integer FRAME_PIXELS = 1920 * 1080,
    parameter integer COUNT_WIDTH = 22
)(
    input  wire        link_clk,
    input  wire        rst,
    input  wire [15:0] link_data,
    input  wire        link_valid,
    input  wire        link_sof,
    input  wire        link_eof,
    output wire        link_ready,

    output reg         write_req,
    input  wire        write_req_ack_mem,
    input  wire        write_fifo_full,
    output reg         write_en,
    output reg  [31:0] write_data,
    input  wire        write_finish_toggle_mem,

    output reg         image_valid,
    output wire        receiving,
    output reg         protocol_error
);

localparam [2:0] ST_IDLE = 3'd0;
localparam [2:0] ST_REQUEST = 3'd1;
localparam [2:0] ST_RECEIVE = 3'd2;
localparam [2:0] ST_WAIT_WRITE = 3'd3;
localparam [2:0] ST_DONE = 3'd4;
localparam [2:0] ST_ERROR = 3'd5;
localparam [2:0] ST_DRAIN_ACK = 3'd6;

reg [2:0] state;
reg [COUNT_WIDTH-1:0] pixel_count;
reg half_pixel;
reg [15:0] first_pixel;
reg ack_meta, ack_sync;
reg finish_meta, finish_sync, finish_seen;
reg frame_write_ack_seen;

assign link_ready = (state == ST_RECEIVE) && !write_fifo_full && !write_en;
assign receiving=state==ST_REQUEST || state==ST_DRAIN_ACK || state==ST_RECEIVE || state==ST_WAIT_WRITE;

always @(posedge link_clk or posedge rst) begin
    if (rst) begin
        ack_meta <= 1'b0;
        ack_sync <= 1'b0;
        finish_meta <= 1'b0;
        finish_sync <= 1'b0;
    end else begin
        ack_meta <= write_req_ack_mem;
        ack_sync <= ack_meta;
        finish_meta <= write_finish_toggle_mem;
        finish_sync <= finish_meta;
    end
end

always @(posedge link_clk or posedge rst) begin
    if (rst) begin
        state <= ST_IDLE;
        pixel_count <= {COUNT_WIDTH{1'b0}};
        half_pixel <= 1'b0;
        first_pixel <= 16'd0;
        write_req <= 1'b0;
        write_en <= 1'b0;
        write_data <= 32'd0;
        image_valid <= 1'b0;
        protocol_error <= 1'b0;
        finish_seen <= 1'b0;
        frame_write_ack_seen <= 1'b0;
    end else begin
        write_en <= 1'b0;
        case (state)
            ST_IDLE: begin
                write_req <= 1'b0;
                if (link_valid && link_sof) begin
                    write_req <= 1'b1;
                    pixel_count <= {COUNT_WIDTH{1'b0}};
                    half_pixel <= 1'b0;
                    image_valid <= 1'b0;
                    frame_write_ack_seen <= ack_sync;
                    finish_seen <= finish_sync;
                    state <= ST_REQUEST;
                end
            end
            ST_REQUEST: begin
                write_req <= 1'b1;
                if (ack_sync) begin
                    write_req <= 1'b0;
                    frame_write_ack_seen <= 1'b1;
                    state <= ST_DRAIN_ACK;
                end
            end
            ST_DRAIN_ACK: if (!ack_sync) state <= ST_RECEIVE;
            ST_RECEIVE: begin
                if (link_valid && link_ready) begin
                    if ((pixel_count == 0) != link_sof) begin
                        protocol_error <= 1'b1;
                        state <= ST_ERROR;
                    end else if ((pixel_count == FRAME_PIXELS - 1) != link_eof) begin
                        protocol_error <= 1'b1;
                        state <= ST_ERROR;
                    end else begin
                        if (!half_pixel) begin
                            first_pixel <= link_data;
                            half_pixel <= 1'b1;
                        end else begin
                            write_data <= {first_pixel, link_data};
                            write_en <= 1'b1;
                            half_pixel <= 1'b0;
                        end
                        if (pixel_count == FRAME_PIXELS - 1) begin
                            pixel_count <= pixel_count + 1'b1;
                            state <= ST_WAIT_WRITE;
                        end else begin
                            pixel_count <= pixel_count + 1'b1;
                        end
                    end
                end
            end
            ST_WAIT_WRITE: begin
                if (finish_sync != finish_seen) begin
                    finish_seen <= finish_sync;
                    image_valid <= frame_write_ack_seen;
                    state <= ST_DONE;
                end
            end
            ST_DONE: begin
                image_valid <= 1'b1;
            end
            ST_ERROR: begin
                write_req <= 1'b0;
                write_en <= 1'b0;
                image_valid <= 1'b0;
                protocol_error <= 1'b1;
            end
            default: begin
                state <= ST_ERROR;
                protocol_error <= 1'b1;
            end
        endcase
    end
end

endmodule
