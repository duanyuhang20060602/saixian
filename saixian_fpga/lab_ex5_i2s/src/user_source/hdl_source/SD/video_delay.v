module video_delay
(
	input                       video_clk,          // Video pixel clock
	input                       rst,
	output                      read_en,            // Read data enable
	input[31:0]                 read_data,          // Two RGB565 pixels per SDRAM word
	input                       read_empty,
	input                       display_valid,
	output reg                  underflow_latched,
	input                      hs,                 // horizontal synchronization
	input                      vs,                 // vertical synchronization
	input                      de,                 // video valid

	output                      hs_r,                 // horizontal synchronization
	output                      vs_r,                 // vertical synchronization
	output                      de_r,                 // video valid
	output[23:0]                vout_data           // RGB888 video data

);
reg [20:0] hs_d;
reg [20:0] vs_d;
reg [20:0] de_d;
reg [23:0] vout_data_r;
reg req_phase;
reg out_phase;
reg word_ok_d;
reg pair_valid;
reg [15:0] second_pixel;

// One SDRAM word is consumed for every two active pixels.
assign read_en = de_d[18] && !req_phase && display_valid && !read_empty;
assign hs_r = hs_d[20];
assign vs_r = vs_d[20];
assign de_r = de_d[20];
assign vout_data = vout_data_r;

function [23:0] rgb565_to_rgb888;
    input [15:0] pixel;
    begin
        rgb565_to_rgb888 = {
            pixel[15:11],pixel[15:13],
            pixel[10:5], pixel[10:9],
            pixel[4:0],  pixel[4:2]
        };
    end
endfunction

always@(posedge video_clk or posedge rst)
begin
	if(rst == 1'b1)
	begin
		vout_data_r <= 24'd0;
		req_phase <= 1'b0;
		out_phase <= 1'b0;
		word_ok_d <= 1'b0;
		pair_valid <= 1'b0;
		second_pixel <= 16'd0;
		underflow_latched <= 1'b0;
	end
	else begin
		word_ok_d <= read_en;

		if (!de_d[18])
			req_phase <= 1'b0;
		else
			req_phase <= ~req_phase;

		if (de_d[18] && !req_phase && display_valid && read_empty)
			underflow_latched <= 1'b1;

		if (!de_d[19]) begin
			out_phase <= 1'b0;
			pair_valid <= 1'b0;
			vout_data_r <= 24'd0;
		end else if (!out_phase) begin
			out_phase <= 1'b1;
			pair_valid <= word_ok_d;
			second_pixel <= read_data[15:0];
			vout_data_r <= word_ok_d ? rgb565_to_rgb888(read_data[31:16]) : 24'd0;
		end else begin
			out_phase <= 1'b0;
			vout_data_r <= pair_valid ? rgb565_to_rgb888(second_pixel) : 24'd0;
		end
	end
end
always @(posedge video_clk or posedge rst)begin
	if(rst)begin
    	hs_d <= 20'b0;
        vs_d <= 20'b0;
        de_d <= 20'b0;
    end
	else begin
    	
    	hs_d <= {hs_d[19:0],hs};
        vs_d <= {vs_d[19:0],vs};
        de_d <= {de_d[19:0],de};
    end
end
endmodule
