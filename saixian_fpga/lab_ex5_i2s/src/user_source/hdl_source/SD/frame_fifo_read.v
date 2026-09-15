`timescale 1ns/1ps
module frame_fifo_read
#(
    parameter MEM_DATA_BITS = 32,
    parameter ADDR_BITS      = 21,
    parameter BURST_BITS     = 9,
    parameter FIFO_DEPTH     = 512,
    parameter BURST_SIZE     = 128,
    parameter FRAME_WIDTH    = 640
)(
    input                            rst,
    input                            mem_clk,
    input                            Sdr_init_done,
    input                            Sdr_init_ref_vld,
    input                            Sdr_busy,
    input                            Sdr_rd_en,
    input                            App_wr_busy,
    output                           O_rd_busy,
    output                           App_rd_en,
    output [ADDR_BITS-1:0]           App_rd_addr,
    input                            read_req,
    output reg                       read_req_ack,
    output                           read_finish,
    input [ADDR_BITS-1:0]            read_addr_0,
    input [ADDR_BITS-1:0]            read_addr_1,
    input [ADDR_BITS-1:0]            read_addr_2,
    input [ADDR_BITS-1:0]            read_addr_3,
    input [1:0]                      read_addr_index,
    input [ADDR_BITS-1:0]            read_len,
    input                            slide_active,
    input [1:0]                      slide_old_index,
    input [1:0]                      slide_new_index,
    input [9:0]                      slide_offset,
    input                            slide_right,
    output reg                       fifo_aclr,
    input [BURST_BITS-1:0]           wrusedw
);

localparam S_IDLE           = 4'd0;
localparam S_ACK            = 4'd1;
localparam S_CHECK_FIFO     = 4'd2;
localparam S_READ_BURST     = 4'd3;
localparam S_READ_BURST_END = 4'd4;
localparam S_END            = 4'd5;
localparam [10:0] FRAME_WIDTH_U = FRAME_WIDTH;

reg read_req_d0, read_req_d1, read_req_d2;
reg [ADDR_BITS-1:0] read_len_d0, read_len_d1, read_len_latch;
reg [1:0] read_addr_index_d0, read_addr_index_d1;
reg slide_active_d0, slide_active_d1;
reg [1:0] slide_old_d0, slide_old_d1, slide_new_d0, slide_new_d1;
reg [9:0] slide_offset_d0, slide_offset_d1;
reg slide_right_d0, slide_right_d1;

reg [3:0] state;
reg [ADDR_BITS-1:0] read_cnt;
reg [BURST_BITS-1:0] burst_cnt;
reg [3:0] rd_delay;
reg App_rd_en_r, App_rd_en_d0;
reg [ADDR_BITS-1:0] App_rd_addr_r;

reg slide_active_latch, slide_right_latch;
reg [9:0] slide_offset_latch;
reg [9:0] issue_x;
reg [ADDR_BITS-1:0] old_row_base, new_row_base;

wire rd_vld = (state == S_READ_BURST && burst_cnt >= BURST_SIZE);
wire rd_burst_finish = rd_vld && (rd_delay == 4'd10);
assign read_finish = (state == S_END);
assign O_rd_busy = (state == S_READ_BURST);
assign App_rd_en = App_rd_en_d0;
assign App_rd_addr = App_rd_addr_r;

function [ADDR_BITS-1:0] select_base;
    input [1:0] index;
    begin
        case (index)
            2'd0: select_base = read_addr_0;
            2'd1: select_base = read_addr_1;
            2'd2: select_base = read_addr_2;
            default: select_base = read_addr_3;
        endcase
    end
endfunction

function [ADDR_BITS-1:0] mapped_address;
    input [9:0] xpos;
    input [ADDR_BITS-1:0] old_base;
    input [ADDR_BITS-1:0] new_base;
    input enabled;
    input move_right;
    input [9:0] offset;
    reg [10:0] split;
    begin
        split = FRAME_WIDTH_U - {1'b0,offset};
        if (!enabled)
            mapped_address = old_base + xpos;
        else if (!move_right) begin
            // Next image: old frame moves left, new frame enters at right.
            if ({1'b0,xpos} < split)
                mapped_address = old_base + xpos + offset;
            else
                mapped_address = new_base + xpos - split;
        end else begin
            // Previous image: old frame moves right, new frame enters at left.
            if (xpos < offset)
                mapped_address = new_base + xpos + split;
            else
                mapped_address = old_base + xpos - offset;
        end
    end
endfunction

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        read_req_d0 <= 0; read_req_d1 <= 0; read_req_d2 <= 0;
        read_len_d0 <= 0; read_len_d1 <= 0;
        read_addr_index_d0 <= 0; read_addr_index_d1 <= 0;
        slide_active_d0 <= 0; slide_active_d1 <= 0;
        slide_old_d0 <= 0; slide_old_d1 <= 0;
        slide_new_d0 <= 0; slide_new_d1 <= 0;
        slide_offset_d0 <= 0; slide_offset_d1 <= 0;
        slide_right_d0 <= 0; slide_right_d1 <= 0;
    end else begin
        read_req_d0 <= read_req; read_req_d1 <= read_req_d0; read_req_d2 <= read_req_d1;
        read_len_d0 <= read_len; read_len_d1 <= read_len_d0;
        read_addr_index_d0 <= read_addr_index; read_addr_index_d1 <= read_addr_index_d0;
        slide_active_d0 <= slide_active; slide_active_d1 <= slide_active_d0;
        slide_old_d0 <= slide_old_index; slide_old_d1 <= slide_old_d0;
        slide_new_d0 <= slide_new_index; slide_new_d1 <= slide_new_d0;
        slide_offset_d0 <= slide_offset; slide_offset_d1 <= slide_offset_d0;
        slide_right_d0 <= slide_right; slide_right_d1 <= slide_right_d0;
    end
end

always @(posedge mem_clk or posedge rst) begin
    if (rst || App_rd_en)
        rd_delay <= 0;
    else if (rd_delay < 4'd10)
        rd_delay <= rd_delay + 1'b1;
end

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        burst_cnt <= 0;
        App_rd_addr_r <= 0;
        App_rd_en_d0 <= 0;
        issue_x <= 0;
        old_row_base <= 0;
        new_row_base <= 0;
        slide_active_latch <= 0;
        slide_right_latch <= 0;
        slide_offset_latch <= 0;
    end else begin
        if (state == S_CHECK_FIFO)
            burst_cnt <= 0;
        else if (App_rd_en)
            burst_cnt <= burst_cnt + 1'b1;

        if (state == S_ACK) begin
            slide_active_latch <= slide_active_d1;
            slide_right_latch <= slide_right_d1;
            slide_offset_latch <= slide_offset_d1;
            issue_x <= 0;
            old_row_base <= select_base(slide_active_d1 ? slide_old_d1 : read_addr_index_d1);
            new_row_base <= select_base(slide_new_d1);
            App_rd_addr_r <= mapped_address(10'd0,
                select_base(slide_active_d1 ? slide_old_d1 : read_addr_index_d1),
                select_base(slide_new_d1), slide_active_d1, slide_right_d1, slide_offset_d1);
        end else if (App_rd_en) begin
            if (issue_x == FRAME_WIDTH - 1) begin
                issue_x <= 0;
                old_row_base <= old_row_base + FRAME_WIDTH_U;
                new_row_base <= new_row_base + FRAME_WIDTH_U;
                App_rd_addr_r <= mapped_address(10'd0,
                    old_row_base + FRAME_WIDTH_U, new_row_base + FRAME_WIDTH_U,
                    slide_active_latch, slide_right_latch, slide_offset_latch);
            end else begin
                issue_x <= issue_x + 1'b1;
                App_rd_addr_r <= mapped_address(issue_x + 1'b1,
                    old_row_base, new_row_base,
                    slide_active_latch, slide_right_latch, slide_offset_latch);
            end
        end

        if (App_rd_en_r && (burst_cnt + App_rd_en < BURST_SIZE))
            App_rd_en_d0 <= 1'b1;
        else
            App_rd_en_d0 <= 1'b0;
    end
end

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        state <= S_IDLE;
        read_len_latch <= 0;
        App_rd_en_r <= 0;
        read_cnt <= 0;
        fifo_aclr <= 0;
        read_req_ack <= 0;
    end else begin
        case (state)
            S_IDLE: begin
                if (read_req_d2 && Sdr_init_done)
                    state <= S_ACK;
                read_req_ack <= 0;
            end
            S_ACK: begin
                if (!read_req_d2) begin
                    state <= S_CHECK_FIFO;
                    fifo_aclr <= 0;
                    read_req_ack <= 0;
                end else begin
                    read_req_ack <= 1;
                    fifo_aclr <= 1;
                    read_len_latch <= read_len_d1;
                end
                read_cnt <= 0;
            end
            S_CHECK_FIFO: begin
                if (read_req_d2)
                    state <= S_ACK;
                else if ((wrusedw < FIFO_DEPTH - BURST_SIZE) && !App_wr_busy) begin
                    state <= S_READ_BURST;
                    App_rd_en_r <= 1;
                end
            end
            S_READ_BURST: begin
                if (rd_burst_finish) begin
                    App_rd_en_r <= 0;
                    state <= S_READ_BURST_END;
                    read_cnt <= read_cnt + BURST_SIZE;
                end
            end
            S_READ_BURST_END: begin
                if (read_req_d2)
                    state <= S_ACK;
                else if (read_cnt < read_len_latch)
                    state <= S_CHECK_FIFO;
                else
                    state <= S_END;
            end
            S_END: state <= S_IDLE;
            default: state <= S_IDLE;
        endcase
    end
end

endmodule
