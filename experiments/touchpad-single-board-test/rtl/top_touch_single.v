`timescale 1ns/1ps
module top_touch_single(
 input clk,hmi_uart_rx,output hmi_uart_tx,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 output HDMI_DDC_SCL,inout HDMI_DDC_SDA
);
wire pixel_clk,serial_clk,locked,rst_pixel,rst_serial;
video_pll u_video_pll(.refclk(clk),.reset(1'b0),.clk0_out(pixel_clk),.clk1_out(serial_clk),.locked(locked));
dual_still_reset_sync rp(.clk(pixel_clk),.arst(!locked),.rst(rst_pixel));
dual_still_reset_sync rs(.clk(serial_clk),.arst(!locked),.rst(rst_serial));
wire [11:0] x;wire [10:0] y;wire de;
wire frame_tick=(x==0 && y==720);
wire [10:0] cx;wire [9:0] cy,raw_x;wire [8:0] raw_y;
wire mode_enabled,contact,click;
wire [15:0] rx_count,error_count,tap_count;wire [1:0] selection;
touch_test_core core(.clk(pixel_clk),.rst(rst_pixel),.uart_rx(hmi_uart_rx),.frame_tick(frame_tick),
 .cursor_x(cx),.cursor_y(cy),.raw_x(raw_x),.raw_y(raw_y),.mode_enabled(mode_enabled),
 .contact(contact),.click(click),.rx_count(rx_count),.error_count(error_count),.tap_count(tap_count),.selection(selection));
wire [23:0] rgb;wire [9:0] b,g,r;
touch_test_scene scene(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(frame_tick),.de(de),.x(x),.y(y),
 .cursor_x(cx),.cursor_y(cy),.raw_x(raw_x),.raw_y(raw_y),.mode_enabled(mode_enabled),.contact(contact),
 .rx_count(rx_count),.error_count(error_count),.tap_count(tap_count),.selection(selection),.rgb(rgb));
hdmi_minimal_tx #(.EXTERNAL_VIDEO(1),.VIDEO_DELAY(2)) video(
 .clk(pixel_clk),.rst(rst_pixel),.rgb_in(rgb),.blue(b),.green(g),.red(r),.hs(),.vs(),.de(de),.frame_start(),.x(x),.y(y));
hdmi_phy_wrapper #(.DEVICE("EG")) phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst_serial),
 .I_tmds_channel_0(b),.I_tmds_channel_1(g),.I_tmds_channel_2(r),.I_tmds_channel_clk(10'b1111100000),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
// Test firmware is receive-only. Leave DDC released; the video mode is fixed.
assign hmi_uart_tx=1'b1;
assign HDMI_DDC_SCL=1'b1;
assign HDMI_DDC_SDA=1'bz;
endmodule
