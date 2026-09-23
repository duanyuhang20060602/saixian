`timescale 1ns/1ps
module tb_slide_reader;

reg clk = 0;
reg rst = 1;
reg read_req = 0;
reg slide_right = 0;
wire read_req_ack;
wire read_finish;
wire app_rd_en;
wire [20:0] app_rd_addr;
wire fifo_aclr;
wire rd_busy;
integer seen;
integer expected;

always #5 clk = ~clk;

frame_fifo_read #(
    .ADDR_BITS(21), .BURST_BITS(4), .FIFO_DEPTH(32),
    .BURST_SIZE(8), .FRAME_WIDTH(8)
) dut (
    .rst(rst), .mem_clk(clk), .Sdr_init_done(1'b1),
    .Sdr_init_ref_vld(1'b0), .Sdr_busy(1'b0), .Sdr_rd_en(1'b0),
    .App_wr_busy(1'b0), .O_rd_busy(rd_busy),
    .App_rd_en(app_rd_en), .App_rd_addr(app_rd_addr),
    .read_req(read_req), .read_req_ack(read_req_ack),
    .read_finish(read_finish),
    .read_addr_0(21'd0), .read_addr_1(21'd100),
    .read_addr_2(21'd200), .read_addr_3(21'd300),
    .read_addr_index(2'd0), .read_len(21'd16),
    .slide_active(1'b1), .slide_old_index(2'd0),
    .slide_new_index(2'd1), .slide_offset(10'd3),
    .slide_right(slide_right), .fifo_aclr(fifo_aclr), .wrusedw(4'd0)
);

function integer expected_address;
    input integer pixel;
    input integer move_right;
    integer x;
    integer row;
    begin
        x = pixel % 8;
        row = pixel / 8;
        if (!move_right) begin
            if (x < 5) expected_address = row * 8 + x + 3;
            else       expected_address = 100 + row * 8 + x - 5;
        end else begin
            if (x < 3) expected_address = 100 + row * 8 + x + 5;
            else       expected_address = row * 8 + x - 3;
        end
    end
endfunction

task check_frame;
    input move_right;
    begin
        slide_right = move_right;
        repeat (3) @(posedge clk);
        @(negedge clk); read_req = 1;
        wait (read_req_ack);
        @(negedge clk); read_req = 0;
        seen = 0;
        while (seen < 16) begin
            @(posedge clk);
            if (app_rd_en) begin
                expected = expected_address(seen, move_right);
                if (app_rd_addr !== expected[20:0]) begin
                    $display("FAIL dir=%0d pixel=%0d got=%0d expected=%0d",
                             move_right, seen, app_rd_addr, expected);
                    $finish;
                end
                seen = seen + 1;
            end
        end
        wait (read_finish);
        repeat (2) @(posedge clk);
    end
endtask

initial begin
    repeat (3) @(posedge clk);
    rst = 0;
    check_frame(0);
    check_frame(1);
    $display("PASS tb_slide_reader");
    $finish;
end

endmodule
