`timescale 1ns/1ps
module top_photo_a(
 input clk,hdmi_hpd,link_clk,input [15:0] link_data,input link_valid,link_sof,link_eof,
 input [3:0] key,input control_rx,hmi_uart_rx,output control_tx,hmi_uart_tx,
 output link_ready,image_ack,output [5:0] seg_sel,output [7:0] seg_data,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout HDMI_DDC_SDA);
wire unused_sd,mem_clk,mem_clk_sft,sys_lock,pixel_clk,serial_clk,video_lock;
wire rst_mem,rst_pixel,rst_serial,rst_link,rst_ref;
sys_pll u_sys_pll(.refclk(clk),.reset(1'b0),.clk0_out(unused_sd),.clk1_out(mem_clk),.clk2_out(mem_clk_sft),.locked(sys_lock));
video_pll u_video_pll(.refclk(clk),.reset(1'b0),.clk0_out(pixel_clk),.clk1_out(serial_clk),.locked(video_lock));
dual_still_reset_sync rm(.clk(mem_clk),.arst(!sys_lock),.rst(rst_mem));
dual_still_reset_sync rp(.clk(pixel_clk),.arst(!video_lock || !sys_lock),.rst(rst_pixel));
dual_still_reset_sync rh(.clk(serial_clk),.arst(!video_lock || !sys_lock),.rst(rst_serial));
dual_still_reset_sync rl(.clk(link_clk),.arst(!sys_lock || !video_lock),.rst(rst_link));
dual_still_reset_sync rr(.clk(clk),.arst(!sys_lock || !video_lock),.rst(rst_ref));
wire req,we,ack,full,finish,rx_done,rx_armed,rx_fault;
wire [31:0] packed_data,read_data,rx_crc;reg finish_toggle,done_toggle;
always @(posedge mem_clk or posedge rst_mem)
 if(rst_mem)finish_toggle<=0;else if(finish)finish_toggle<=~finish_toggle;
always @(posedge link_clk or posedge rst_link)
 if(rst_link)done_toggle<=0;else if(rx_done)done_toggle<=~done_toggle;
wire arm_toggle,abort_toggle,arm,abort;
wire [1:0] receive_slot,active_slot,new_slot,ready_slot;
photo_event_sync sa(.clk(link_clk),.rst(rst_link),.toggle(arm_toggle),.pulse(arm));
photo_event_sync sb(.clk(link_clk),.rst(rst_link),.toggle(abort_toggle),.pulse(abort));
photo_link_receiver #(.ENABLE_CRC(0),.LEGACY_TIMING(1)) rx(.clk(link_clk),.rst(rst_link),.arm(arm),.abort(abort),.data(link_data),.valid(link_valid),.sof(link_sof),.eof(link_eof),
 .ready(link_ready),.armed(rx_armed),.busy(),.write_req(req),.write_ack(ack),.full(full),.write_en(we),.write_data(packed_data),
 .finish_toggle(finish_toggle),.done(rx_done),.fault(rx_fault),.frame_crc(rx_crc));
assign image_ack=done_toggle;
wire read_req,read_en,read_ack,read_finish,read_empty,init_done;
wire transition_active,slide_right,display_valid,frame_commit,ready_toggle,ready_right;
wire [2:0] transition_mode;wire [10:0] slide_offset;wire [5:0] darkness;
frame_store #(.FLIP(0)) store(.write_slot(receive_slot),.read_slot(active_slot),.new_slot(new_slot),
 .slide_active(transition_active),.slide_right(slide_right),.slide_offset({1'b0,slide_offset[10:1]}),.transition_mode(transition_mode),
 .mem_clk(mem_clk),.mem_clk_sft(mem_clk_sft),.rst(rst_mem),
 .write_clk(link_clk),.write_req(req),.write_en(we && !full),.write_data(packed_data),.write_ack(ack),.write_finish(finish),.write_full(full),
 .read_clk(pixel_clk),.read_req(read_req),.read_en(read_en),.read_ack(read_ack),.read_finish(read_finish),
 .read_empty(read_empty),.read_data(read_data),.init_done(init_done));
wire hs,vs,de,fs;wire [11:0] x;wire [10:0] y;wire [9:0] blue,green,red;
wire blank_start=x==0 && y==720;
wire [23:0] raw_rgb,final_rgb;
// The FIFO reader takes two cycles, photo enhancement seven, adjustment
// eight and style/fade/multiply/range four: 21 clocks in all.
hdmi_minimal_tx #(.EXTERNAL_VIDEO(1),.VIDEO_DELAY(21)) u_tx(.clk(pixel_clk),.rst(rst_pixel),.rgb_in(final_rgb),
 .blue(blue),.green(green),.red(red),.hs(hs),.vs(vs),.de(de),.frame_start(fs),.x(x),.y(y));
wire armed,started,underflow;
frame_pixels pixels(.clk(pixel_clk),.rst(rst_pixel),.de(de),.x(x),.y(y),.image_valid(display_valid),
 .read_ack(read_ack),.empty(read_empty),.data(read_data),.read_req(read_req),.read_en(read_en),.rgb(raw_rgb),
 .armed(armed),.output_started(started),.underflow(underflow));
saixian_transition transition(.clk(pixel_clk),.rst(rst_pixel),.frame_tick(blank_start),.frame_ready_toggle(ready_toggle),
 .ready_buf_idx(ready_slot),.ready_slide_right(ready_right),.active_buf_idx(active_slot),.slide_new_buf_idx(new_slot),
 .frame_commit_toggle(frame_commit),.display_valid(display_valid),.transition_active(transition_active),
 .transition_mode(transition_mode),.slide_offset(slide_offset),.slide_right(slide_right),.transition_level(darkness));
wire [3:0] presses;
genvar k;
generate for(k=0;k<4;k=k+1)begin:keys
 saixian_key_debounce #(.CLK_FREQ_HZ(75000000)) button(.clk(pixel_clk),.rst(rst_pixel),.key_n(key[k]),.press_pulse(presses[k]));
end endgenerate
wire hmi_prev,hmi_next,setting_valid,reset_defaults,page_notify;wire [2:0] setting_id,page_id;wire [7:0] setting_value;
saixian_hmi_uart #(.CLK_FREQ_HZ(75000000)) screen_rx(.clk(pixel_clk),.rst(rst_pixel),.uart_rx(hmi_uart_rx),
 .prev_pulse(hmi_prev),.next_pulse(hmi_next),.setting_valid(setting_valid),.setting_id(setting_id),.setting_value(setting_value),
 .reset_defaults_pulse(reset_defaults),.page_id(page_id),.page_notify_pulse(page_notify));
wire settings_mode;wire [3:0] brightness,contrast,saturation,volume;wire [1:0] sharpness,enhancement;wire invert,vintage;
// Diagnostic build: HMI/key settings cannot enable enhancement or sharpening.
assign sharpness=2'd0;assign enhancement=2'd0;
saixian_settings_controller #(.CLK_FREQ_HZ(75000000)) settings(.clk(pixel_clk),.rst(rst_pixel),.carousel_mode(1'b1),
 .key_next_item(presses[0]),.key_decrease(presses[1]),.key_enter_exit(presses[2]),.key_increase(presses[3]),
 .hmi_setting_valid(setting_valid),.hmi_setting_id(setting_id),.hmi_setting_value(setting_value),.hmi_reset_defaults(reset_defaults),
 .settings_mode(settings_mode),.setting_item(),.volume_setting(volume),.brightness_setting(brightness),.contrast_setting(contrast),
 .saturation_setting(saturation),.sharpness_setting(),.invert_setting(invert),.vintage_setting(vintage),.enhancement_setting());
reg armed_meta,armed_sync,fault_meta,fault_sync;
always @(posedge pixel_clk or posedge rst_pixel)
 if(rst_pixel)begin armed_meta<=0;armed_sync<=0;fault_meta<=0;fault_sync<=0;end
 else begin armed_meta<=rx_armed;armed_sync<=armed_meta;fault_meta<=rx_fault;fault_sync<=fault_meta;end
wire done_pixel,busy;wire [2:0] count,current;wire [3:0] error,control_state;
photo_event_sync sd(.clk(pixel_clk),.rst(rst_pixel),.toggle(done_toggle),.pulse(done_pixel));
photo_control_a #(.CHECK_FRAME_CRC(0)) ctrl(.clk(pixel_clk),.rst(rst_pixel),.uart_rx(control_rx),.uart_tx(control_tx),
 .previous(!settings_mode && (presses[0] || hmi_prev)),.next(!settings_mode && (presses[3] || hmi_next)),
 .active_slot(active_slot),.new_slot(new_slot),.transition_active(transition_active),.commit_toggle(frame_commit),
 .receive_slot(receive_slot),.arm_toggle(arm_toggle),.abort_toggle(abort_toggle),.rx_armed(armed_sync),.rx_done(done_pixel),
 .rx_fault(fault_sync),.rx_crc(rx_crc),.ready_toggle(ready_toggle),.ready_slot(ready_slot),.ready_right(ready_right),
 .image_count(count),.current_image(current),.busy(busy),.error(error),.debug_state(control_state));
saixian_hmi_status_tx #(.CLK_FREQ_HZ(75000000)) screen_tx(.clk(pixel_clk),.rst(rst_pixel),.image_count(count),
 .audio_count(3'd0),.error_code(error>7 ? 3'd7:error[2:0]),.initializing(count==0),.page_id(page_id),
 .refresh_request(page_notify || setting_valid || reset_defaults),.sharpness(sharpness),.brightness(brightness),.contrast(contrast),
 .saturation(saturation),.volume(volume),.invert(invert),.vintage(vintage),.event_state(4'd0),.minutes(7'd0),.seconds(6'd0),
 .uart_tx(hmi_uart_tx),.command_sent_pulse());
// Snapshot settings in blanking. Delay coordinates alongside the FIFO RGB.
reg [3:0] bf,cf,sf;reg [1:0] shf,ef;reg invf,vinf;
reg [1:0] de_pipe,vs_pipe;reg [10:0] x0,x1;reg [9:0] y0,y1;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin bf<=4;cf<=4;sf<=4;shf<=0;ef<=0;invf<=0;vinf<=0;de_pipe<=0;vs_pipe<=0;x0<=0;x1<=0;y0<=0;y1<=0;end
 else begin
  de_pipe<={de_pipe[0],de};vs_pipe<={vs_pipe[0],vs};x0<=x[10:0];x1<=x0;y0<=y[9:0];y1<=y0;
  if(blank_start)begin bf<=brightness;cf<=contrast;sf<=saturation;shf<=sharpness;ef<=enhancement;invf<=invert;vinf<=vintage;end
 end
end
wire [23:0] enhanced,adjusted,styled;wire enhanced_de,enhanced_vs;wire [10:0] enhanced_x;wire [9:0] enhanced_y;
saixian_adaptive_enhance #(.WIDTH(1280),.SPLIT_X(640),.PHOTO_SMOOTH(1)) enhance(
 .clk(pixel_clk),.rst(rst_pixel),.de(de_pipe[1]),.vs(vs_pipe[1]),.frame_tick(blank_start),
 .statistics_enable(display_valid && !transition_active),.x(x1),.y(y1),.rgb_in(raw_rgb),.mode(ef),.strength(shf),
 .rgb_out(enhanced),.de_out(enhanced_de),.vs_out(enhanced_vs),.x_out(enhanced_x),.y_out(enhanced_y),.gain_out());
saixian_picture_adjust_pipe adjust(.clk(pixel_clk),.rst(rst_pixel),.de(enhanced_de),.x(enhanced_x),.rgb_in(enhanced),
 .brightness_setting(bf),.contrast_setting(cf),.saturation_setting(sf),.sharpness_setting(shf),.rgb_out(adjusted));
saixian_hmi_color_style style(.rgb_in(adjusted),.invert(invf),.vintage(vinf),.rgb_out(styled));
function [7:0] fade_channel;
 input [7:0] value;input [5:0] level;reg [15:0] p;reg [7:0] faded;
 begin faded=value>({2'd0,level}<<2) ? value-({2'd0,level}<<2):0;
 fade_channel=faded;end
endfunction
reg [23:0] style_rgb,fade_rgb,range_rgb;reg [15:0] range_r,range_g,range_b;
always @(posedge pixel_clk or posedge rst_pixel)begin
 if(rst_pixel)begin style_rgb<=0;fade_rgb<=0;range_r<=0;range_g<=0;range_b<=0;range_rgb<=24'h101010;end
 else begin
  style_rgb<=styled;
  fade_rgb<={fade_channel(style_rgb[23:16],darkness),fade_channel(style_rgb[15:8],darkness),fade_channel(style_rgb[7:0],darkness)};
  range_r<=fade_rgb[23:16]*8'd219+16'd128;range_g<=fade_rgb[15:8]*8'd219+16'd128;range_b<=fade_rgb[7:0]*8'd219+16'd128;
  range_rgb<={8'd16+range_r[15:8],8'd16+range_g[15:8],8'd16+range_b[15:8]};
 end
end
assign final_rgb=range_rgb;
hdmi_phy_wrapper #(.DEVICE("EG")) u_hdmi_phy(.I_pixel_clk(pixel_clk),.I_serial_clk(serial_clk),.I_rst(rst_serial),
 .I_tmds_channel_0(blue),.I_tmds_channel_1(green),.I_tmds_channel_2(red),.I_tmds_channel_clk(10'b1111100000),
 .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
wire scan_valid,scan_fault,clock_valid,clock_fault;
hdmi_scan_monitor #(.HT(1650),.VT(750),.HA(1280),.VA(720),.HS(40),.VS(5)) u_scan(
 .clk(pixel_clk),.rst(rst_pixel),.x(x),.y(y),.de(de),.hs(hs),.vs(vs),.frame_start(fs),.valid(scan_valid),.fault(scan_fault));
hdmi_pixel_clock_monitor #(.EXPECTED_PIXELS(7500000),.TOLERANCE_PIXELS(75000)) u_clock_check(
 .ref_clk(clk),.pixel_clk(pixel_clk),.arst(!video_lock),.valid(clock_valid),.fault(clock_fault));
reg hpd_meta,hpd_sync;reg [17:0] status_meta,status_sync;
always @(posedge clk or posedge rst_ref)
 if(rst_ref)begin hpd_meta<=0;hpd_sync<=0;status_meta<=0;status_sync<=0;end
 else begin hpd_meta<=hdmi_hpd;hpd_sync<=hpd_meta;
  status_meta<={count,(display_valid ? current+3'd1:3'd0),control_state,error,
   (error!=0 || underflow || scan_fault || clock_fault ? 4'd9:busy ? 4'd3:display_valid ? 4'd5:4'd2)};
  status_sync<=status_meta;end
photo_status #(.CLK_HZ(50000000)) status(.clk(clk),.rst(rst_ref),.status(hpd_sync ? status_sync[3:0]:4'd0),
 .error(status_sync[7:4]),.state(status_sync[11:8]),.image(status_sync[14:12]),.count(status_sync[17:15]),
 .diagnostic_page(3'd0),.diagnostic_crc(16'd0),.seg_sel(seg_sel),.seg_data(seg_data));
assign HDMI_DDC_SCL=1'b1;assign HDMI_DDC_SDA=1'bz;
endmodule
