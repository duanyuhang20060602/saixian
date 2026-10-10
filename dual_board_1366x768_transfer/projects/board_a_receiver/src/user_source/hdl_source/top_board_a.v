`timescale 1ns/1ps
module top_dual_still_display(
 input clk,hdmi_hpd,link_clk,input [15:0] link_data,input link_valid,link_sof,link_eof,
 output link_ready,image_ack,output [5:0] seg_sel,output [7:0] seg_data,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA);
wire unused_sd,mem_clk,mem_clk_sft,sys_lock,pixel_clk,serial_clk,video_lock;
wire rst_mem,rst_pixel,rst_serial,rst_link,rst_ref;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(unused_sd),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
video_pll u_video_pll(.refclk(clk),.reset(1'b0),.clk0_out(pixel_clk),.clk1_out(serial_clk),.locked(video_lock));
dual_still_reset_sync rm(.clk(mem_clk),.arst(!sys_lock),.rst(rst_mem));
dual_still_reset_sync rp(.clk(pixel_clk),.arst(!video_lock || !sys_lock),.rst(rst_pixel));
dual_still_reset_sync rh(.clk(serial_clk),.arst(!video_lock || !sys_lock),.rst(rst_serial));
dual_still_reset_sync rl(.clk(link_clk),.arst(!sys_lock),.rst(rst_link));
dual_still_reset_sync rr(.clk(clk),.arst(!sys_lock || !video_lock),.rst(rst_ref));
wire req,we,ack,full,finish,valid,protocol_error,receiving;
wire [31:0] packed_data,read_data;reg finish_toggle;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)finish_toggle<=0;else if(finish)finish_toggle<=~finish_toggle;
dual_still_link_rx #(.FRAME_PIXELS(1049088),.COUNT_WIDTH(21)) rx(
 .link_clk(link_clk),.rst(rst_link),.link_data(link_data),.link_valid(link_valid),.link_sof(link_sof),.link_eof(link_eof),
 .link_ready(link_ready),.write_req(req),.write_req_ack_mem(ack),.write_fifo_full(full),
 .write_en(we),.write_data(packed_data),.write_finish_toggle_mem(finish_toggle),
 .image_valid(valid),.protocol_error(protocol_error),.receiving(receiving));
assign image_ack=valid;
wire read_req,read_en,read_ack,read_finish,read_empty,init_done;
frame_store #(.FLIP(0)) store(.mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_mem),
 .write_clk(link_clk),.write_req(req),.write_en(we),.write_data(packed_data),
 .write_ack(ack),.write_finish(finish),.write_full(full),
 .read_clk(pixel_clk),.read_req(read_req),.read_en(read_en),.read_ack(read_ack),
 .read_finish(read_finish),.read_empty(read_empty),.read_data(read_data),.init_done(init_done));
reg valid_meta,valid_sync;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin valid_meta<=0;valid_sync<=0;end
 else begin valid_meta<=valid;valid_sync<=valid_meta;end
wire hs,vs,de,fs,armed,started,underflow;
wire [11:0] x;wire [10:0] y;wire [23:0] rgb;
wire [9:0] blue,green,red;
hdmi_minimal_tx #(.EXTERNAL_VIDEO(1)) u_tx(.clk(pixel_clk),.rst(rst_pixel),.rgb_in(rgb),
 .blue(blue),.green(green),.red(red),.hs(hs),.vs(vs),.de(de),.frame_start(fs),.x(x),.y(y));
frame_pixels pixels(.clk(pixel_clk),.rst(rst_pixel),.de(de),.x(x),.y(y),
 .image_valid(valid_sync),.read_ack(read_ack),.empty(read_empty),.data(read_data),
 .read_req(read_req),.read_en(read_en),.rgb(rgb),.armed(armed),.output_started(started),.underflow(underflow));
hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst_serial),
 .I_tmds_channel_0(blue),.I_tmds_channel_1(green),.I_tmds_channel_2(red),.I_tmds_channel_clk(10'b1111100000),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
wire scan_valid,scan_fault,clock_valid,clock_fault;
hdmi_scan_monitor #(.HT(1500),.VT(800),.HA(1366),.VA(768),.HS(56),.VS(3)) u_scan(
 .clk(pixel_clk),.rst(rst_pixel),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.frame_start(fs),.valid(scan_valid),.fault(scan_fault));
hdmi_pixel_clock_monitor #(.EXPECTED_PIXELS(7200000),.TOLERANCE_PIXELS(72000)) u_clock_check(
 .ref_clk(clk),.pixel_clk(pixel_clk),.arst(!video_lock),.valid(clock_valid),.fault(clock_fault));
reg hpd_meta=0,hpd_sync=0;
always @(posedge clk)begin hpd_meta<=hdmi_hpd;hpd_sync<=hpd_meta;end
reg [7:0] status_meta,status_sync;
always @(posedge clk or posedge rst_ref)
 if(rst_ref)begin status_meta<=0;status_sync<=0;end
 else begin
  status_meta<={protocol_error,underflow,clock_fault,scan_fault,started,valid_sync,receiving,scan_valid && clock_valid};
  status_sync<=status_meta;
 end
wire [3:0] digit=!hpd_sync ? 4'd0 : (!video_lock || !sys_lock) ? 4'd1 :
 status_sync[7] ? 4'd9 : status_sync[6] ? 4'd8 : status_sync[5] ? 4'd7 : status_sync[4] ? 4'd6 :
 status_sync[3] ? 4'd5 : status_sync[2] ? 4'd4 : status_sync[1] ? 4'd3 : status_sync[0] ? 4'd2 : 4'd1;
status_segments status(.digit(digit),.segments(seg_data));
assign seg_sel=6'b111110;
assign HDMI_DDC_SCL=1'b1;assign HDMI_DDC_SDA=1'bz;
endmodule
