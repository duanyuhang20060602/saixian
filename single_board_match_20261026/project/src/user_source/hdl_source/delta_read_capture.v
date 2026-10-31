// ReadAlign candidate for physical-board E2D: SDRAM data appears one word
// ahead of valid. Capture EVERY cycle, including before the first valid word.
// The known-pattern test and complete cache CRC still gate all playback.
module delta_read_capture(input clk,input rst,input [31:0] raw_data,
 output reg [31:0] captured_data);
always @(posedge clk)begin
 if(rst)captured_data<=0;else captured_data<=raw_data;
end
endmodule
