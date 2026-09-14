module saixian_video_tracker(
    input  wire       clk,
    input  wire       rst,
    input  wire       vs,
    input  wire       de,
    output reg  [9:0] x,
    output reg  [8:0] y,
    output wire       frame_tick
);

reg vs_d;
reg de_d;
reg first_line;

assign frame_tick = vs_d & ~vs;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        vs_d       <= 1'b1;
        de_d       <= 1'b0;
        first_line <= 1'b1;
        x           <= 10'd0;
        y           <= 9'd0;
    end else begin
        vs_d <= vs;
        de_d <= de;

        if (frame_tick) begin
            x           <= 10'd0;
            y           <= 9'd0;
            first_line  <= 1'b1;
        end else if (de) begin
            if (!de_d) begin
                x <= 10'd0;
                if (first_line)
                    first_line <= 1'b0;
                else
                    y <= y + 9'd1;
            end else begin
                x <= x + 10'd1;
            end
        end else begin
            x <= 10'd0;
        end
    end
end

endmodule
