// These examples instantiate the exact cores used by the 2.0 production path.
// Compile together with SD/frame_fifo_read.v, saixian_key_debounce.v and
// SD/seg_scan.v. No copied implementation can drift from the real design.
module saixian_light_transition_demo(
    input [10:0] x, offset, input [9:0] y,
    input [20:0] old_row_base, new_row_base,
    input enable, right, input [2:0] effect,
    output [20:0] address
);
saixian_frame_mapper #(.FRAME_WIDTH(1280)) core(
    .xpos(x),.ypos(y),.old_base(old_row_base),.new_base(new_row_base),
    .enabled(enable),.move_right(right),.effect(effect),.offset(offset),.address(address));
endmodule

module saixian_light_key_demo #(
    parameter CLK_FREQ_HZ=75000000, DEBOUNCE_MS=20
)(input clk,rst,key_n,output pressed);
saixian_key_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) core(
    .clk(clk),.rst(rst),.key_n(key_n),.press_pulse(pressed));
endmodule

module saixian_light_scan_demo #(
    parameter CLK_FREQ=50000000, SCAN_FREQ=200
)(input clk,rst,input [47:0] digits,output [5:0] select,output [7:0] segments);
seg_scan #(.CLK_FREQ(CLK_FREQ),.SCAN_FREQ(SCAN_FREQ)) core(
    .clk(clk),.rst_n(!rst),.seg_sel(select),.seg_data(segments),
    .seg_data_0(digits[7:0]),.seg_data_1(digits[15:8]),.seg_data_2(digits[23:16]),
    .seg_data_3(digits[31:24]),.seg_data_4(digits[39:32]),.seg_data_5(digits[47:40]));
endmodule
